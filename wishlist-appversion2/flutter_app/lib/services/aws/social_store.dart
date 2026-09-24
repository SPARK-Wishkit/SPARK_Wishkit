import 'dart:math';

import '../../models/models.dart';
import 'gql_documents.dart';
import 'gql_runner.dart';
import 'user_data_store.dart';

/// 3-1단계: 팔로우 · 친구 목록 · 친구 공개 위시리스트를 AWS 로 처리한다.
///
/// - 팔로우 관계는 Follow 표 한 줄씩. 팔로워/팔로잉 "수"는 저장하지 않고 센다.
/// - 친구의 탭·상품은 직접 읽지 않고, 서버 함수가 "공개 항목만, 메모 없이" 돌려준다.
class AwsSocialStore {
  AwsSocialStore({GqlRunner? runner}) : _gql = runner ?? const AmplifyGqlRunner();

  final GqlRunner _gql;

  static const _pageSize = 1000;
  static const _maxPages = 50;
  static const _parallel = 8;
  static const directoryLimit = 80;
  static const _allTabId = 'all';

  // ── 팔로우 ──────────────────────────────────────────────────

  /// 내가 팔로우하는 사람들의 uid.
  Future<List<String>> followingIds(String uid) async {
    final rows = await _listAll(Gql.listFollowing, 'listFollows', uid);
    return rows.map((r) => r['followeeId'] as String).toList();
  }

  /// 나를 팔로우하는 사람들의 uid.
  Future<List<String>> followerIds(String uid) async {
    final rows =
        await _listAll(Gql.listFollowers, 'listFollowsByFollowee', uid);
    return rows.map((r) => r['followerId'] as String).toList();
  }

  /// 팔로우 / 언팔로우. 이미 그 상태면 조용히 넘어간다 (버튼 연타 대비).
  Future<void> setFollowing({
    required String myUid,
    required String targetUid,
    required bool follow,
  }) async {
    if (myUid == targetUid) return;
    final key = {'followerId': myUid, 'followeeId': targetUid};
    try {
      await _gql.mutate(
        follow ? Gql.createFollow : Gql.deleteFollow,
        variables: {'input': key},
      );
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
    }
  }

  /// 내 팔로워 목록에서 [followerUid] 를 뺀다. (상대의 팔로우 관계를 지움)
  Future<void> removeFollower({
    required String myUid,
    required String followerUid,
  }) async {
    if (myUid == followerUid) return;
    try {
      await _gql.mutate(Gql.deleteFollow, variables: {
        'input': {'followerId': followerUid, 'followeeId': myUid},
      });
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
    }
  }

  /// 회원 탈퇴: 내가 한 팔로우와 나를 향한 팔로우를 모두 지운다.
  Future<void> deleteAllFollows(String uid) async {
    final following = await followingIds(uid);
    final followers = await followerIds(uid);
    await _runLimited([
      for (final t in following)
        () => setFollowing(myUid: uid, targetUid: t, follow: false),
      for (final f in followers)
        () => removeFollower(myUid: uid, followerUid: f),
    ]);
  }

  // ── 사람 목록 ───────────────────────────────────────────────

  /// uid 목록 → 공개 프로필. 없는(탈퇴한) 사람은 빠진다. 이름순.
  Future<List<AppUser>> loadUsers(List<String> uids) async {
    final results = <AppUser>[];
    final jobs = <Future<void> Function()>[
      for (final id in uids.toSet())
        () async {
          final data = await _gql.query(
            Gql.getProfile,
            variables: {'ownerId': id},
          );
          final p = data['getProfile'];
          if (p is Map) {
            results.add(
              AwsUserDataStore.userFromProfileRow(p.cast<String, dynamic>()),
            );
          }
        },
    ];
    await _runLimited(jobs);
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }

  /// 친구 찾기 목록 (나 제외, 최대 [directoryLimit]명).
  /// "위시리스트 N · 아이템 M" 숫자는 서버 함수 한 번으로 모두 받아온다.
  Future<List<Friend>> loadDirectory({
    required String myUid,
    required Set<String> following,
  }) async {
    final data = await _gql.query(
      Gql.listProfiles,
      variables: {'limit': directoryLimit + 1, 'nextToken': null},
    );
    final rows = ((data['listProfiles'] as Map?)?['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .where((r) => r['ownerId'] != myUid)
        .take(directoryLimit)
        .toList();
    if (rows.isEmpty) return [];

    final counts = await _counts([for (final r in rows) r['ownerId'] as String]);

    final out = [
      for (final r in rows)
        () {
          final user = AwsUserDataStore.userFromProfileRow(r);
          final c = counts[user.uid];
          return Friend(
            id: user.uid,
            name: user.name,
            username: user.handle,
            avatar: user.avatarUrl,
            isFollowing: following.contains(user.uid),
            wishlistCount: c?.$1 ?? 0,
            itemCount: c?.$2 ?? 0,
          );
        }(),
    ];
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Future<Map<String, (int, int)>> _counts(List<String> ownerIds) async {
    try {
      final data = await _gql.query(
        Gql.publicWishlistCounts,
        variables: {'ownerIds': ownerIds},
      );
      return {
        for (final c in (data['publicWishlistCounts'] as List? ?? const [])
            .whereType<Map>())
          c['ownerId'] as String: (
            (c['listCount'] as num?)?.toInt() ?? 0,
            (c['itemCount'] as num?)?.toInt() ?? 0,
          ),
      };
    } on AwsDataException {
      // 숫자는 부가 정보라, 실패해도 목록 자체는 보여 준다.
      return const {};
    }
  }

  // ── 친구 공개 위시리스트 ────────────────────────────────────

  /// 내가 팔로우하는 친구들의 공개 탭('전체' 제외)과 그 안의 공개 상품.
  Future<List<FriendWishlist>> loadFriendWishlists(List<Friend> friends) async {
    final byFriend = <String, List<FriendWishlist>>{};
    final targets = friends.where((f) => f.isFollowing).toList();
    await _runLimited([
      for (final friend in targets)
        () async {
          try {
            byFriend[friend.id] = await _friendWishlists(friend);
          } on AwsDataException {
            byFriend[friend.id] = const []; // 한 명 실패가 전체를 막지 않게
          }
        },
    ]);
    // 친구 순서를 입력 순서대로 유지
    return [for (final f in targets) ...?byFriend[f.id]];
  }

  Future<List<FriendWishlist>> _friendWishlists(Friend friend) async {
    final data = await _gql.query(
      Gql.publicWishlist,
      variables: {'ownerId': friend.id},
    );
    final w = data['publicWishlist'];
    if (w is! Map) return const [];

    final products = <Product>[];
    for (final p in (w['products'] as List? ?? const []).whereType<Map>()) {
      final id = int.tryParse(p['productId'] as String? ?? '');
      if (id == null) continue;
      products.add(Product(
        id: id,
        listId: p['listId'] as String? ?? _allTabId,
        name: p['name'] as String? ?? '',
        price: (p['price'] as num?)?.toInt() ?? 0,
        image: p['image'] as String? ?? '',
        platform: p['platform'] as String? ?? '',
        originalPrice: (p['originalPrice'] as num?)?.toInt(),
        discount: (p['discount'] as num?)?.toInt(),
        productUrl: p['productUrl'] as String?,
        isPublic: true,
      ));
    }

    return [
      for (final t in (w['tabs'] as List? ?? const []).whereType<Map>())
        if (t['tabId'] != _allTabId)
          FriendWishlist(
            id: '${friend.id}_${t['tabId']}',
            friendId: friend.id,
            friendName: friend.name,
            listName: t['name'] as String? ?? '',
            isPublic: true,
            items: products.where((p) => p.listId == t['tabId']).toList(),
          ),
    ];
  }

  // ── 공통 ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _listAll(
    String document,
    String field,
    String uid,
  ) async {
    final items = <Map<String, dynamic>>[];
    String? next;
    var pages = 0;
    do {
      final data = await _gql.query(document, variables: {
        'ownerId': uid,
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
