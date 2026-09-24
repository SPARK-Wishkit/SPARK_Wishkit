import 'dart:convert';

import 'package:figmadesign/services/aws/gql_runner.dart';

/// 테스트용 가짜 AppSync.
///
/// 실제 생성된 리졸버·권한과 같은 규칙을 따른다 (amplify/data/resource.ts 기준):
///  - create: 같은 키가 있으면 ConditionalCheckFailed
///  - update/delete: 키가 없으면 ConditionalCheckFailed
///  - 표마다 누가 읽고 쓰는지 (아래 _readableByAnyone / _canWrite)
///  - 서버 함수 publicWishlist(Counts): 공개 항목만, 메모 없이, '전체' 탭 제외
class FakeAppSync implements GqlRunner {
  FakeAppSync(this.caller);

  /// 지금 로그인한 사람의 uid (Cognito sub)
  String caller;

  final tables = <String, Map<String, Map<String, dynamic>>>{};
  int mutationCount = 0;

  static const _keys = {
    'Profile': ['ownerId'],
    'PrivateProfile': ['ownerId'],
    'Handle': ['handleLower'],
    'WishTab': ['ownerId', 'tabId'],
    'WishProduct': ['ownerId', 'productId'],
    'Review': ['ownerId', 'reviewId'],
    'Follow': ['followerId', 'followeeId'],
    'SentBasket': ['ownerId', 'basketId'],
    'ReceivedBasket': ['recipientId', 'basketId'],
    'BasketThread': ['threadId'],
    'BasketComment': ['threadId', 'commentId'],
    'Notification': ['recipientId', 'notificationId'],
  };

  /// 표마다 "주인" 칸
  static const _ownerField = {
    'Follow': 'followerId',
    'ReceivedBasket': 'recipientId',
    'Notification': 'recipientId',
  };

  /// 앱이 직접 만들 수 없는 표 (서버 함수만)
  static const _serverCreateOnly = {
    'ReceivedBasket', 'Notification', 'BasketThread', 'BasketComment',
  };

  /// 앱이 직접 고칠 수 없는 표
  static const _noClientUpdate = {
    'Handle', 'Follow', 'ReceivedBasket', 'BasketThread', 'BasketComment',
  };

  /// 앱이 직접 지울 수 없는 표
  static const _noClientDelete = {'BasketThread', 'BasketComment'};

  /// list 쿼리 이름 → (표, 조회 기준 필드)
  static const _lists = {
    'listWishTabs': ('WishTab', 'ownerId'),
    'listWishProducts': ('WishProduct', 'ownerId'),
    'listReviews': ('Review', 'ownerId'),
    'listFollows': ('Follow', 'followerId'),
    'listFollowsByFollowee': ('Follow', 'followeeId'),
    'listProfiles': ('Profile', null),
    'listSentBaskets': ('SentBasket', 'ownerId'),
    'listReceivedBaskets': ('ReceivedBasket', 'recipientId'),
    'listBasketComments': ('BasketComment', 'threadId'),
    'listNotifications': ('Notification', 'recipientId'),
  };

  /// 로그인한 사람이면 남의 것도 읽을 수 있는 표
  static const _readableByAnyone = {'Profile', 'Handle', 'Review', 'Follow'};

  Map<String, Map<String, dynamic>> table(String model) =>
      tables.putIfAbsent(model, () => {});

  String _key(String model, Map<String, dynamic> v) =>
      _keys[model]!.map((k) => '${v[k]}').join('#');

  Never _fail(String type) => throw AwsDataException(type, errorType: type);

  bool _owns(String model, Map<String, dynamic> row) =>
      row[_ownerField[model] ?? 'ownerId'] == caller;

  bool _canDelete(String model, Map<String, dynamic> row) =>
      _owns(model, row) || (model == 'Follow' && row['followeeId'] == caller);

  static String _op(String document) =>
      RegExp(r'\{\s*(\w+)\(').firstMatch(document)!.group(1)!;

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) async {
    final op = _op(document);

    if (op == 'publicWishlist') {
      return {op: _publicWishlist(variables['ownerId'] as String)};
    }
    if (op == 'publicWishlistCounts') {
      final ids = (variables['ownerIds'] as List).cast<String>().toSet();
      return {
        op: [
          for (final id in ids.take(100))
            () {
              final w = _publicWishlist(id);
              return {
                'ownerId': id,
                'listCount': (w['tabs'] as List).length,
                'itemCount': (w['products'] as List).length,
              };
            }(),
        ],
      };
    }

    if (op.startsWith('get')) {
      final model = op.substring(3);
      final row = table(model)[_key(model, variables)];
      if (row != null && !_readableByAnyone.contains(model) && !_owns(model, row)) {
        _fail('Unauthorized');
      }
      return {op: row == null ? null : {...row}};
    }

    final (model, field) = _lists[op]!;
    Iterable<Map<String, dynamic>> rows = table(model).values;
    if (model == 'BasketComment') {
      // 참여자만 읽기: 목록에서 내가 참여자인 댓글만 남긴다 (실제 AppSync 도 거른다)
      final want = variables['ownerId'];
      rows = rows.where((r) =>
          r['threadId'] == want &&
          (r['participantIds'] as List).contains(caller));
    } else if (field != null) {
      final want = variables[field] ?? variables['ownerId'];
      if (!_readableByAnyone.contains(model) && want != caller) {
        _fail('Unauthorized');
      }
      rows = rows.where((r) => r[field] == want);
    }
    final limit = variables['limit'] as int?;
    final items = rows.map((r) => {...r}).toList();
    return {
      op: {
        'items': limit == null ? items : items.take(limit).toList(),
        'nextToken': null,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) async {
    mutationCount++;
    final op = _op(document);
    if (_serverOps.contains(op)) return {op: _server(op, variables)};
    final input = Map<String, dynamic>.from(variables['input'] as Map);
    final kind = op.startsWith('create')
        ? 'create'
        : op.startsWith('update')
            ? 'update'
            : 'delete';
    final model = op.substring(kind.length);
    final t = table(model);
    final key = _key(model, input);
    final existing = t[key];

    switch (kind) {
      case 'create':
        if (_serverCreateOnly.contains(model)) _fail('Unauthorized');
        if (!_owns(model, input)) _fail('Unauthorized');
        if (existing != null) _fail('DynamoDB:ConditionalCheckFailedException');
        t[key] = input;
      case 'update':
        if (_noClientUpdate.contains(model)) _fail('Unauthorized');
        if (existing == null) _fail('DynamoDB:ConditionalCheckFailedException');
        if (!_owns(model, existing)) _fail('Unauthorized');
        existing.addAll(input);
      case 'delete':
        if (_noClientDelete.contains(model)) _fail('Unauthorized');
        if (existing == null) _fail('DynamoDB:ConditionalCheckFailedException');
        if (!_canDelete(model, existing)) _fail('Unauthorized');
        t.remove(key);
    }
    return {op: {...input}};
  }

  /// amplify/functions/public-wishlist/logic.ts 와 같은 규칙
  Map<String, dynamic> _publicWishlist(String ownerId) {
    final tabs = table('WishTab')
        .values
        .where((r) =>
            r['ownerId'] == ownerId && r['isPublic'] == true && r['tabId'] != 'all')
        .toList()
      ..sort((a, b) =>
          ((a['sortOrder'] as int?) ?? 0).compareTo((b['sortOrder'] as int?) ?? 0));
    final products = table('WishProduct')
        .values
        .where((r) => r['ownerId'] == ownerId && r['isPublic'] == true)
        .map((r) => {...r}..remove('memo')..remove('ownerId')..remove('isPublic'))
        .toList();
    return {
      'ownerId': ownerId,
      'tabs': [
        for (final t in tabs)
          {
            'tabId': t['tabId'],
            'name': t['name'],
            'colorHex': t['colorHex'],
            'sortOrder': t['sortOrder'],
          },
      ],
      'products': products,
    };
  }

  // ── 서버 함수 흉내 (amplify/functions/social-actions/logic.ts 와 같은 규칙) ──

  static const _serverOps = {
    'sendBasket', 'addBasketComment', 'editBasketComment',
    'removeBasketComment', 'notifyFollow',
  };
  int _seq = 0;
  String _id() => 'srv${++_seq}';
  Never _code(String code) =>
      throw AwsDataException(code, errorType: 'Lambda:Unhandled');

  Map<String, dynamic> _author(String uid) {
    final p = table('Profile')[uid] ?? _code('PROFILE_MISSING');
    return {
      'uid': uid,
      'name': p['name'],
      'handle': p['handle'],
      'avatar': p['avatarUrl'] ?? '',
    };
  }

  void _notify(String to, Map<String, dynamic> from, String type, String msg,
      String related, {String? id}) {
    if (to == from['uid']) return;
    final nid = id ?? _id();
    table('Notification')['$to#$nid'] = {
      'recipientId': to,
      'notificationId': nid,
      'type': type,
      'read': false,
      'data': {
        'id': nid, 'type': type, 'fromUid': from['uid'], 'fromName': from['name'],
        'fromHandle': from['handle'], 'fromAvatar': from['avatar'],
        'message': msg, 'relatedId': related, 'read': false,
        'createdAt': DateTime.utc(2026, 9, 25, 0, 0, _seq).toIso8601String(),
      },
    };
  }

  Object? _server(String op, Map<String, dynamic> v) {
    final now = DateTime.utc(2026, 9, 25, 0, 0, _seq).toIso8601String();
    switch (op) {
      case 'sendBasket': {
        final from = _author(caller);
        final threadId = v['threadId'] as String;
        final recipients = (v['recipientIds'] as List)
            .cast<String>()
            .toSet()
            .where((id) => id != caller && table('Profile').containsKey(id))
            .toList();
        if (recipients.isEmpty) _code('NO_RECIPIENTS');
        final thread = table('BasketThread')[threadId];
        if (thread != null && thread['ownerId'] != caller) _code('THREAD_CONFLICT');
        final participants = {
          ...((thread?['participantIds'] as List?)?.cast<String>() ?? const []),
          caller,
          ...recipients,
        }.toList();
        table('BasketThread')[threadId] = {
          'threadId': threadId, 'ownerId': caller, 'participantIds': participants,
        };
        for (final c in table('BasketComment').values) {
          if (c['threadId'] == threadId) c['participantIds'] = participants;
        }
        final items = (jsonDecode(v['items'] as String) as List)
            .map((e) => Map<String, dynamic>.from(e as Map)..remove('memo'))
            .toList();
        for (final r in recipients) {
          final bid = _id();
          table('ReceivedBasket')['$r#$bid'] = {
            'recipientId': r, 'basketId': bid, 'fromUid': caller,
            'data': jsonEncode({
              'id': bid, 'title': '${from['name']}의 살까말까',
              'ownerName': from['name'], 'fromUid': caller,
              'fromHandle': from['handle'], 'fromAvatar': from['avatar'],
              'items': items, 'createdAt': now, 'channels': ['friends'],
              'memo': v['memo'] ?? '', 'threadId': threadId,
            }),
          };
          _notify(r, from, 'basket', '${from['name']} 님이 살까말까 장바구니를 보냈어요', threadId);
        }
        return recipients.length;

      }
      case 'addBasketComment': {
        final threadId = v['threadId'] as String;
        final text = (v['text'] as String).trim();
        if (text.isEmpty) _code('INVALID_INPUT');
        var thread = table('BasketThread')[threadId];
        if (thread == null) {
          thread = {
            'threadId': threadId, 'ownerId': caller,
            'participantIds': {caller, ...((v['participantIds'] as List?)?.cast<String>() ?? const [])}.toList(),
          };
          table('BasketThread')[threadId] = thread;
        }
        final participants = (thread['participantIds'] as List).cast<String>();
        if (!participants.contains(caller)) _code('NOT_PARTICIPANT');
        final existing = table('BasketComment').values.where((c) => c['threadId'] == threadId).toList();
        var parentId = (v['parentId'] as String?) ?? '';
        final parent = existing.where((c) => c['commentId'] == parentId).firstOrNull;
        if (parent != null && (parent['parentId'] as String? ?? '').isNotEmpty) {
          parentId = parent['parentId'] as String;
        }
        final from = _author(caller);
        final cid = _id();
        final comment = {
          'id': cid, 'threadId': threadId, 'parentId': parentId,
          'authorUid': caller, 'authorName': from['name'],
          'authorHandle': from['handle'], 'authorAvatar': from['avatar'],
          'text': text, 'createdAt': now, 'updatedAt': null,
        };
        table('BasketComment')['$threadId#$cid'] = {
          'threadId': threadId, 'commentId': cid, 'authorId': caller,
          'parentId': parentId, 'participantIds': participants,
          'data': jsonEncode(comment),
        };
        final owner = thread['ownerId'] as String;
        final targets = <String>{};
        if (owner != caller) targets.add(owner);
        if (parentId.isNotEmpty) {
          final p = existing.where((c) => c['commentId'] == parentId).firstOrNull;
          if (p != null && p['authorId'] != caller) targets.add(p['authorId'] as String);
        } else if (caller == owner) {
          targets.addAll(participants.where((id) => id != caller));
        }
        for (final t in targets) {
          _notify(t, from, 'comment', '댓글', threadId);
        }
        return jsonEncode(comment);

      }
      case 'editBasketComment': {
        final row = table('BasketComment')['${v['threadId']}#${v['commentId']}'];
        if (row == null) _code('COMMENT_NOT_FOUND');
        if (row['authorId'] != caller) _code('NOT_AUTHOR');
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        row['data'] = jsonEncode({...data, 'text': (v['text'] as String).trim(), 'updatedAt': now});
        return true;

      }
      case 'removeBasketComment': {
        final key = '${v['threadId']}#${v['commentId']}';
        final row = table('BasketComment')[key];
        if (row == null) return true;
        if (row['authorId'] != caller) _code('NOT_AUTHOR');
        table('BasketComment').remove(key);
        return true;

      }
      case 'notifyFollow': {
        final target = v['targetId'] as String;
        if (target == caller) return false;
        if (!table('Follow').containsKey('$caller#$target')) _code('NOT_FOLLOWING');
        final from = _author(caller);
        _notify(target, from, 'follow', '팔로우', '', id: 'follow-$caller');
        return true;
      }
    }
    return null;
  }
}
