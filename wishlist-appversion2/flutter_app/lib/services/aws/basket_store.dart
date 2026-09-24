import 'dart:convert';
import 'dart:math';

import '../../models/models.dart';
import 'gql_documents.dart';
import 'gql_runner.dart';
import 'polling.dart';

/// 3-2단계: 살까말까 · 댓글 · 알림을 AWS 로 처리한다.
///
/// - 남의 받은함·알림함·댓글방에 쓰는 일은 서버 함수(sendBasket, addBasketComment …)만 한다.
///   보낸 사람 이름·사진도 서버가 DB 프로필에서 채운다.
/// - "지켜보기(watch)"는 주기적으로 새로고침하고, 내가 뭔가 한 직후에는 바로 새로고침한다.
class AwsBasketStore {
  AwsBasketStore({
    GqlRunner? runner,
    RefreshHub? hub,
    this.inboxInterval = const Duration(seconds: 20),
    this.commentsInterval = const Duration(seconds: 5),
  })  : _gql = runner ?? const AmplifyGqlRunner(),
        _hub = hub ?? RefreshHub();

  final GqlRunner _gql;
  final RefreshHub _hub;

  /// 알림·받은 살까말까 새로고침 간격
  final Duration inboxInterval;

  /// 댓글 화면을 보고 있을 때 새로고침 간격
  final Duration commentsInterval;

  static const _pageSize = 200;
  static const _maxPages = 20;
  static const _parallel = 8;
  static const inboxLimit = 100;

  static String _notificationsKey(String uid) => 'notifications:$uid';
  static String _receivedKey(String uid) => 'received:$uid';
  static String _commentsKey(String threadId) => 'comments:$threadId';

  // ── 보낸 살까말까 (본인만) ──────────────────────────────────

  Future<List<SharedBasket>> loadSentBaskets(String uid) async {
    final rows = await _listAll(Gql.listSentBaskets, 'listSentBaskets', uid);
    final list = [
      for (final r in rows)
        if (decodeAwsJson(r['data']) case final d?)
          SharedBasket.fromJson(d..['id'] = d['id'] ?? r['basketId']),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(inboxLimit).toList();
  }

  Future<void> upsertSentBasket(String uid, SharedBasket basket) async {
    final input = {
      'ownerId': uid,
      'basketId': basket.id,
      'data': jsonEncode(basket.toJson()),
    };
    try {
      await _gql.mutate(Gql.createSentBasket, variables: {'input': input});
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
      await _gql.mutate(Gql.updateSentBasket, variables: {'input': input});
    }
  }

  // ── 받은 살까말까 ───────────────────────────────────────────

  Future<List<SharedBasket>> loadReceivedBaskets(String uid) async {
    final rows =
        await _listAll(Gql.listReceivedBaskets, 'listReceivedBaskets', uid);
    final list = [
      for (final r in rows)
        if (decodeAwsJson(r['data']) case final d?)
          SharedBasket.fromJson(d..['id'] = r['basketId']),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(inboxLimit).toList();
  }

  Stream<List<SharedBasket>> watchReceivedBaskets(String uid) => pollingStream(
        load: () => loadReceivedBaskets(uid),
        interval: inboxInterval,
        hub: _hub,
        key: _receivedKey(uid),
        signature: (list) => list.map((b) => b.id).join(','),
      );

  /// 살까말까 보내기. 받은함 · 알림 · 댓글방은 서버가 만든다.
  /// 받은 사람 수를 돌려준다 (탈퇴한 사람 등은 빠질 수 있음).
  Future<int> sendBasket({
    required List<String> recipientUids,
    required List<Product> items,
    required String threadId,
    String memo = '',
  }) async {
    final data = await _call(() => _gql.mutate(Gql.sendBasket, variables: {
          'threadId': threadId,
          'recipientIds': recipientUids,
          'items': jsonEncode(items.map((p) => p.toJson()).toList()),
          'memo': memo,
        }));
    _hub.refresh(_commentsKey(threadId));
    return (data['sendBasket'] as num?)?.toInt() ?? 0;
  }

  // ── 댓글 ───────────────────────────────────────────────────

  Future<List<BasketComment>> loadComments(String threadId) async {
    if (threadId.isEmpty) return const [];
    final rows = await _listAll(
      Gql.listBasketComments,
      'listBasketComments',
      threadId,
    );
    return [
      for (final r in rows)
        if (decodeAwsJson(r['data']) case final d?)
          BasketComment.fromJson(d..['id'] = r['commentId']),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Stream<List<BasketComment>> watchComments(String threadId) {
    if (threadId.isEmpty) return Stream.value(const []);
    return pollingStream(
      load: () => loadComments(threadId),
      interval: commentsInterval,
      hub: _hub,
      key: _commentsKey(threadId),
      signature: (list) => list
          .map((c) => '${c.id}|${c.text}|${c.updatedAt?.toIso8601String()}')
          .join(','),
    );
  }

  Future<void> addComment({
    required String threadId,
    required String text,
    String parentId = '',
    List<String> participantIds = const [],
    String memo = '',
  }) async {
    if (threadId.isEmpty || text.trim().isEmpty) return;
    await _call(() => _gql.mutate(Gql.addBasketComment, variables: {
          'threadId': threadId,
          'text': text,
          'parentId': parentId.isEmpty ? null : parentId,
          'participantIds': participantIds,
          'memo': memo,
        }));
    _hub.refresh(_commentsKey(threadId));
  }

  Future<void> editComment({
    required String threadId,
    required String commentId,
    required String text,
  }) async {
    if (text.trim().isEmpty) throw Exception('댓글을 입력해 주세요.');
    await _call(() => _gql.mutate(Gql.editBasketComment, variables: {
          'threadId': threadId,
          'commentId': commentId,
          'text': text,
        }));
    _hub.refresh(_commentsKey(threadId));
  }

  Future<void> removeComment({
    required String threadId,
    required String commentId,
  }) async {
    await _call(() => _gql.mutate(Gql.removeBasketComment, variables: {
          'threadId': threadId,
          'commentId': commentId,
        }));
    _hub.refresh(_commentsKey(threadId));
  }

  // ── 알림 ───────────────────────────────────────────────────

  Future<List<AppNotification>> loadNotifications(String uid) async {
    final rows =
        await _listAll(Gql.listNotifications, 'listNotifications', uid);
    final list = <AppNotification>[];
    for (final r in rows) {
      final d = decodeAwsJson(r['data']);
      if (d == null) continue;
      d['id'] = r['notificationId'];
      d['read'] = r['read'] == true; // 읽음 여부는 칸 값이 기준
      d['type'] = d['type'] ?? r['type'];
      list.add(AppNotification.fromJson(d));
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(inboxLimit).toList();
  }

  Stream<List<AppNotification>> watchNotifications(String uid) =>
      pollingStream(
        load: () => loadNotifications(uid),
        interval: inboxInterval,
        hub: _hub,
        key: _notificationsKey(uid),
        signature: (list) => list.map((n) => '${n.id}|${n.read}').join(','),
      );

  Future<void> markNotificationsRead(String uid, List<String> ids) async {
    if (ids.isEmpty) return;
    await _runLimited([
      for (final id in ids.toSet())
        () async {
          try {
            await _gql.mutate(Gql.markNotificationRead, variables: {
              'input': {'recipientId': uid, 'notificationId': id, 'read': true},
            });
          } on AwsDataException catch (e) {
            if (!e.isConditionalCheckFailed) rethrow; // 이미 지워진 알림
          }
        },
    ]);
    _hub.refresh(_notificationsKey(uid));
  }

  /// 팔로우 알림 요청. 서버가 실제 팔로우 여부를 확인한다. 실패해도 팔로우 자체엔 영향 없음.
  Future<void> notifyFollow(String targetUid) async {
    try {
      await _gql.mutate(Gql.notifyFollow, variables: {'targetId': targetUid});
    } on AwsDataException {
      // 알림은 부가 기능
    }
  }

  // ── 회원 탈퇴 ─────────────────────────────────────────────

  /// 내 알림 · 받은 살까말까 · 보낸 살까말까 기록을 지운다.
  /// (남의 댓글방에 쓴 내 댓글은 대화 흐름을 위해 남긴다 — 기존 동작과 같음)
  Future<void> deleteAll(String uid) async {
    final notes =
        await _listAll(Gql.listNotifications, 'listNotifications', uid);
    final received =
        await _listAll(Gql.listReceivedBaskets, 'listReceivedBaskets', uid);
    final sent = await _listAll(Gql.listSentBaskets, 'listSentBaskets', uid);
    Future<void> del(String doc, Map<String, dynamic> key) async {
      try {
        await _gql.mutate(doc, variables: {'input': key});
      } on AwsDataException catch (e) {
        if (!e.isConditionalCheckFailed) rethrow;
      }
    }

    await _runLimited([
      for (final n in notes)
        () => del(Gql.deleteNotification,
            {'recipientId': uid, 'notificationId': n['notificationId']}),
      for (final b in received)
        () => del(Gql.deleteReceivedBasket,
            {'recipientId': uid, 'basketId': b['basketId']}),
      for (final b in sent)
        () => del(Gql.deleteSentBasket,
            {'ownerId': uid, 'basketId': b['basketId']}),
    ]);
  }

  // ── 공통 ───────────────────────────────────────────────────

  /// 서버 함수 호출. 약속된 오류 코드를 한국어 문구로 바꿔 던진다.
  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() run,
  ) async {
    try {
      return await run();
    } on AwsDataException catch (e) {
      final message = switch (e.serverCode) {
        'NO_RECIPIENTS' => '보낼 수 있는 친구가 없어요.',
        'TOO_MANY_RECIPIENTS' => '한 번에 50명까지 보낼 수 있어요.',
        'TOO_MANY_ITEMS' => '한 번에 상품 100개까지 보낼 수 있어요.',
        'THREAD_CONFLICT' => '공유 번호가 겹쳤어요. 다시 보내 주세요.',
        'NOT_PARTICIPANT' => '이 살까말까에 참여한 사람만 댓글을 쓸 수 있어요.',
        'NOT_AUTHOR' => '내 댓글만 고치거나 지울 수 있어요.',
        'COMMENT_NOT_FOUND' => '댓글을 찾을 수 없어요.',
        'TOO_LONG' => '글이 너무 길어요.',
        'PROFILE_MISSING' => '프로필 정보를 찾지 못했어요. 다시 로그인해 주세요.',
        'INVALID_INPUT' => '입력한 내용을 다시 확인해 주세요.',
        _ => null,
      };
      if (message != null) throw Exception(message);
      rethrow;
    }
  }

  /// 파티션 키 하나로 목록 전체를 읽는다. (문서들의 변수 이름은 모두 $ownerId)
  Future<List<Map<String, dynamic>>> _listAll(
    String document,
    String field,
    String partitionValue,
  ) async {
    final items = <Map<String, dynamic>>[];
    String? next;
    var pages = 0;
    do {
      final data = await _gql.query(document, variables: {
        'ownerId': partitionValue,
        'limit': _pageSize,
        'nextToken': next,
      });
      final conn = data[field];
      if (conn is! Map) break;
      for (final item in (conn['items'] as List? ?? const [])) {
        if (item is Map) items.add(item.cast<String, dynamic>());
      }
      next = conn['nextToken'] as String?;
      pages++;
    } while (next != null && pages < _maxPages);
    return items;
  }

  Future<void> _runLimited(List<Future<void> Function()> jobs) async {
    for (var i = 0; i < jobs.length; i += _parallel) {
      final end = min(i + _parallel, jobs.length);
      await Future.wait([for (final job in jobs.sublist(i, end)) job()]);
    }
  }
}
