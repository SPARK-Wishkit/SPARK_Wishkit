import 'dart:convert';
import 'dart:math';

import '../../auth/auth_validators.dart';
import '../../models/models.dart';
import '../../theme/avatar_presets.dart';
import 'gql_documents.dart';
import 'gql_runner.dart';

/// 2단계: "내가 쓰는 데이터"를 AWS(AppSync + DynamoDB)에 저장한다.
///
/// 프로필 · 아이디 · 탭 · 상품 · 리뷰 · (본인 전용) 푸시 토큰/숨긴 피드.
/// AccountRepository 가 같은 이름의 함수를 이 클래스로 넘긴다.
/// 화면·AppStore 는 이 클래스를 직접 쓰지 않는다.
class AwsUserDataStore {
  AwsUserDataStore({GqlRunner? runner, Random? random})
      : _gql = runner ?? const AmplifyGqlRunner(),
        _random = random ?? Random.secure();

  final GqlRunner _gql;
  final Random _random;

  static const allTabId = 'all';
  static const _pageSize = 1000;
  static const _maxPages = 50;
  static const _parallel = 8;

  // ─────────────────────────────────────────────────────────────
  // 프로필
  // ─────────────────────────────────────────────────────────────

  /// 내 프로필. 없으면 null. 이메일은 본인만 읽을 수 있어서, 남의 uid 면 비어 있다.
  Future<AppUser?> loadProfile(String uid) async {
    final data = await _gql.query(Gql.getProfile, variables: {'ownerId': uid});
    final p = data['getProfile'];
    if (p is! Map) return null;
    var email = '';
    try {
      email = (await _loadPrivate(uid))?['email'] as String? ?? '';
    } on AwsDataException catch (e) {
      if (!e.isUnauthorized) rethrow;
    }
    return _userFrom(p.cast<String, dynamic>(), email: email);
  }

  /// 로그인 직후 호출. 프로필이 없으면 가입 초안(name, handle)으로 만든다.
  ///
  /// 순서: 아이디 선점 → 비공개 정보 → 공개 프로필 → 기본 탭.
  /// 중간에 앱이 꺼져도 다음 로그인 때 빠진 부분만 다시 만든다.
  Future<void> ensureProfile({
    required String uid,
    required String email,
    String? name,
    String? handle,
  }) async {
    final existing = await _gql.query(
      Gql.getProfile,
      variables: {'ownerId': uid},
    );
    if (existing['getProfile'] is Map) {
      await _ensurePrivate(uid, email);
      return;
    }

    final wanted = AuthValidators.normalizeHandle(handle ?? '');
    final base = wanted.isNotEmpty ? wanted : '@${_emailLocal(email)}';
    final claimed = await _claimHandleWithFallback(uid, base, email);

    await _ensurePrivate(uid, email);

    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : _emailLocal(email);
    await _createOrIgnoreExisting(Gql.createProfile, {
      'ownerId': uid,
      'handle': claimed,
      'handleLower': claimed.toLowerCase(),
      'name': resolvedName,
      'avatarUrl': _defaultAvatar(claimed),
      'followers': 0,
      'following': 0,
    });
    await _seedDefaultTabs(uid);
  }

  /// 이름·사진·아이디 변경. 아이디가 바뀌면 새 아이디를 먼저 선점하고, 성공해야 옛 아이디를 푼다.
  Future<void> updateProfile(
    String uid,
    AppUser user, {
    String? previousHandle,
  }) async {
    final next = AuthValidators.normalizeHandle(user.handle);
    final prev = AuthValidators.normalizeHandle(previousHandle ?? '');
    final handleChanged = prev.isNotEmpty && prev != next;

    if (handleChanged) {
      final invalid = AuthValidators.handle(next);
      if (invalid != null) throw Exception(invalid);
      final ok = await _tryClaimHandle(uid, next, user.email);
      if (!ok) throw Exception('이미 사용 중인 아이디예요.');
    }

    await _gql.mutate(Gql.updateProfile, variables: {
      'input': {
        'ownerId': uid,
        'handle': next,
        'handleLower': next.toLowerCase(),
        'name': user.name,
        'avatarUrl': user.avatarUrl,
      },
    });

    if (handleChanged) {
      await _deleteHandleIfMine(uid, prev);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 아이디 (Handle)
  // ─────────────────────────────────────────────────────────────

  /// 가입 전·아이디 변경 전 중복 확인. 사용 가능하면 true.
  /// [exceptUid] 의 아이디라면(= 내 아이디) 사용 가능으로 본다.
  Future<bool> isHandleAvailable(String handle, {String? exceptUid}) async {
    final row = await _getHandle(handle);
    if (row == null) return true;
    return exceptUid != null && row['ownerId'] == exceptUid;
  }

  /// 기존 코드와의 호환용. 사용 중이면 예외를 던진다.
  Future<void> assertHandleAvailable(String handle, {String? exceptUid}) async {
    if (!await isHandleAvailable(handle, exceptUid: exceptUid)) {
      throw Exception('이미 사용 중인 아이디예요.');
    }
  }

  /// 아이디로 가입 이메일(가려진 형태)을 찾는다. 없으면 null.
  Future<String?> findMaskedEmailByHandle(String handle) async {
    final row = await _getHandle(handle);
    final masked = row?['maskedEmail'] as String?;
    return (masked == null || masked.isEmpty) ? null : masked;
  }

  Future<Map<String, dynamic>?> _getHandle(String handle) async {
    final key = AuthValidators.normalizeHandle(handle).toLowerCase();
    if (key.isEmpty) return null;
    final data = await _gql.query(
      Gql.getHandle,
      variables: {'handleLower': key},
      // 로그인 전(가입·계정 찾기)과 후(아이디 변경) 모두 불린다.
      auth: GqlAuth.auto,
    );
    final row = data['getHandle'];
    return row is Map ? row.cast<String, dynamic>() : null;
  }

  /// 원하는 아이디를 선점한다. 이미 남이 쓰고 있으면 뒤에 숫자를 붙여 다시 시도한다.
  /// (가입 직전에 중복 확인을 하므로 거의 일어나지 않지만, 동시에 가입하는 경우 대비)
  Future<String> _claimHandleWithFallback(
    String uid,
    String wanted,
    String email,
  ) async {
    if (await _tryClaimHandle(uid, wanted, email)) return wanted;
    final body = wanted.replaceFirst('@', '');
    final trimmed = body.length > 15 ? body.substring(0, 15) : body;
    for (var i = 0; i < 5; i++) {
      final candidate = '@${trimmed}_${1000 + _random.nextInt(9000)}';
      if (await _tryClaimHandle(uid, candidate, email)) return candidate;
    }
    throw Exception('아이디를 만들지 못했어요. 잠시 후 다시 시도해 주세요.');
  }

  /// 선점 성공(또는 이미 내 것)이면 true, 남이 쓰고 있으면 false.
  Future<bool> _tryClaimHandle(String uid, String handle, String email) async {
    final key = handle.toLowerCase();
    try {
      await _gql.mutate(Gql.createHandle, variables: {
        'input': {
          'handleLower': key,
          'ownerId': uid,
          'maskedEmail': email.isEmpty ? null : AuthValidators.maskEmail(email),
        },
      });
      return true;
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
      final row = await _getHandle(key);
      return row?['ownerId'] == uid;
    }
  }

  Future<void> _deleteHandleIfMine(String uid, String handle) async {
    final key = handle.toLowerCase();
    if (key.isEmpty) return;
    try {
      await _gql.mutate(Gql.deleteHandle, variables: {
        'input': {'handleLower': key},
      });
    } on AwsDataException catch (e) {
      // 이미 없거나 내 것이 아니면 조용히 넘어간다.
      if (!e.isConditionalCheckFailed && !e.isUnauthorized) rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 본인 전용 정보 (이메일 · 푸시 토큰 · 숨긴 피드)
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _loadPrivate(String uid) async {
    final data = await _gql.query(
      Gql.getPrivateProfile,
      variables: {'ownerId': uid},
    );
    final row = data['getPrivateProfile'];
    return row is Map ? row.cast<String, dynamic>() : null;
  }

  Future<void> _ensurePrivate(String uid, String email) async {
    await _createOrIgnoreExisting(Gql.createPrivateProfile, {
      'ownerId': uid,
      'email': email,
      'fcmTokens': <String>[],
      'hiddenFeedBaskets': <String>[],
    });
  }

  Future<void> _updatePrivateList(
    String uid,
    String field,
    Set<String> Function(Set<String> current) change,
  ) async {
    final row = await _loadPrivate(uid);
    if (row == null) return;
    final current = _stringSet(row[field]);
    final next = change({...current});
    if (next.length == current.length && next.containsAll(current)) return;
    await _gql.mutate(Gql.updatePrivateProfile, variables: {
      'input': {'ownerId': uid, field: next.toList()},
    });
  }

  Future<void> saveFcmToken(String uid, String token) async {
    if (token.isEmpty) return;
    await _updatePrivateList(uid, 'fcmTokens', (s) => s..add(token));
  }

  Future<void> removeFcmToken(String uid, String token) async {
    if (token.isEmpty) return;
    await _updatePrivateList(uid, 'fcmTokens', (s) => s..remove(token));
  }

  Future<Set<String>> loadHiddenFeedBaskets(String uid) async {
    return _stringSet((await _loadPrivate(uid))?['hiddenFeedBaskets']);
  }

  Future<void> hideFeedBaskets(String uid, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _updatePrivateList(uid, 'hiddenFeedBaskets', (s) => s..addAll(list));
  }

  Future<void> unhideFeedBaskets(String uid, Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _updatePrivateList(
      uid,
      'hiddenFeedBaskets',
      (s) => s..removeAll(list),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 탭
  // ─────────────────────────────────────────────────────────────

  /// '전체' 탭이 맨 앞, 나머지는 저장된 순서대로.
  /// (이름순이 아니라 사용자가 정한 순서를 저장해서, 다시 켜도 순서가 유지된다)
  Future<List<WishlistTab>> loadTabs(String uid) async {
    var rows = await _listAll(Gql.listTabs, 'listWishTabs', uid);
    if (rows.isEmpty) {
      await _seedDefaultTabs(uid);
      rows = await _listAll(Gql.listTabs, 'listWishTabs', uid);
    }
    rows.sort((a, b) {
      if (a['tabId'] == allTabId) return -1;
      if (b['tabId'] == allTabId) return 1;
      final byOrder = _int(a['sortOrder']).compareTo(_int(b['sortOrder']));
      if (byOrder != 0) return byOrder;
      return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
    });
    return rows.map(_tabFrom).toList();
  }

  /// 탭 목록을 순서대로 저장하고, 탭의 공개 여부를 그 탭의 상품에도 맞춘다.
  /// (지워진 탭은 [deleteTab] 으로 따로 지운다 — 기존 동작과 같음)
  Future<void> saveTabs(String uid, List<WishlistTab> tabs) async {
    // 이미 있는 탭은 바로 "수정", 새 탭만 "만들기" — 실패 후 재시도하는 왕복을 줄인다.
    final existing = {
      for (final r in await _listAll(Gql.listTabs, 'listWishTabs', uid))
        r['tabId'] as String,
    };
    final jobs = <Future<void> Function()>[
      for (var i = 0; i < tabs.length; i++)
        () => _gql.mutate(
              existing.contains(tabs[i].id) ? Gql.updateTab : Gql.createTab,
              variables: {'input': _tabInput(uid, tabs[i], i)},
            ),
    ];
    await _runLimited(jobs);

    final tabPublic = {for (final t in tabs) t.id: t.isPublic};
    final products = await _listAll(Gql.listProducts, 'listWishProducts', uid);
    final fixes = <Future<void> Function()>[];
    for (final p in products) {
      final want = tabPublic[p['listId']] ?? false;
      if (p['isPublic'] != want) {
        fixes.add(() => _gql.mutate(Gql.updateProduct, variables: {
              'input': {
                'ownerId': uid,
                'productId': p['productId'],
                'isPublic': want,
              },
            }));
      }
    }
    await _runLimited(fixes);
  }

  Future<void> deleteTab(String uid, String tabId) async {
    await _deleteIgnoringMissing(Gql.deleteTab, {'ownerId': uid, 'tabId': tabId});
  }

  /// 새 계정은 고정 '전체' 탭 하나로 시작한다.
  Future<void> _seedDefaultTabs(String uid) async {
    await _createOrIgnoreExisting(
      Gql.createTab,
      _tabInput(
        uid,
        WishlistTab(id: allTabId, name: '전체', isPublic: true),
        0,
      ),
    );
  }

  Map<String, dynamic> _tabInput(String uid, WishlistTab t, int order) => {
        'ownerId': uid,
        'tabId': t.id,
        'name': t.name,
        'isPublic': t.isPublic,
        'colorHex': t.colorHex,
        'sortOrder': order,
      };

  WishlistTab _tabFrom(Map<String, dynamic> r) => WishlistTab(
        id: r['tabId'] as String,
        name: r['name'] as String? ?? '',
        isPublic: r['isPublic'] as bool? ?? true,
        colorHex: r['colorHex'] as String?,
      );

  // ─────────────────────────────────────────────────────────────
  // 상품
  // ─────────────────────────────────────────────────────────────

  /// 상품의 공개 여부가 탭과 다르면 탭 기준으로 바로잡는다. (기존 동작과 같음)
  Future<List<Product>> loadProducts(String uid) async {
    final tabs = await _listAll(Gql.listTabs, 'listWishTabs', uid);
    final tabPublic = {
      for (final t in tabs) t['tabId'] as String: t['isPublic'] as bool? ?? false,
    };
    final rows = await _listAll(Gql.listProducts, 'listWishProducts', uid);
    final products = <Product>[];
    final fixes = <Future<void> Function()>[];
    for (final r in rows) {
      final want = tabPublic[r['listId']] ?? false;
      if (r['isPublic'] != want) {
        r['isPublic'] = want;
        fixes.add(() => _gql.mutate(Gql.updateProduct, variables: {
              'input': {
                'ownerId': uid,
                'productId': r['productId'],
                'isPublic': want,
              },
            }));
      }
      final p = _productFrom(r);
      if (p != null) products.add(p);
    }
    await _runLimited(fixes);
    products.sort((a, b) => a.id.compareTo(b.id));
    return products;
  }

  Future<void> upsertProduct(String uid, Product product) async {
    await _upsert(
      create: Gql.createProduct,
      update: Gql.updateProduct,
      input: {
        'ownerId': uid,
        'productId': '${product.id}',
        'listId': product.listId,
        'name': product.name,
        'price': product.price,
        'image': product.image,
        'platform': product.platform,
        'originalPrice': product.originalPrice,
        'discount': product.discount,
        'productUrl': product.productUrl,
        'memo': product.memo,
        'isPublic': product.isPublic,
      },
    );
  }

  Future<void> deleteProduct(String uid, int productId) async {
    await _deleteIgnoringMissing(
      Gql.deleteProduct,
      {'ownerId': uid, 'productId': '$productId'},
    );
  }

  Product? _productFrom(Map<String, dynamic> r) {
    final id = int.tryParse(r['productId'] as String? ?? '');
    if (id == null) return null;
    return Product(
      id: id,
      listId: r['listId'] as String? ?? allTabId,
      name: r['name'] as String? ?? '',
      price: _int(r['price']),
      image: r['image'] as String? ?? '',
      platform: r['platform'] as String? ?? '',
      originalPrice: _intOrNull(r['originalPrice']),
      discount: _intOrNull(r['discount']),
      productUrl: r['productUrl'] as String?,
      memo: r['memo'] as String?,
      isPublic: r['isPublic'] as bool? ?? false,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 리뷰
  // ─────────────────────────────────────────────────────────────

  Future<List<ProductReview>> loadReviews(String uid) async {
    final rows = await _listAll(Gql.listReviews, 'listReviews', uid);
    final list = <ProductReview>[];
    for (final r in rows) {
      final data = _jsonMap(r['data']);
      if (data == null) continue;
      data['id'] = data['id'] ?? r['reviewId'];
      list.add(ProductReview.fromJson(data));
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> upsertReview(String uid, ProductReview review) async {
    await _upsert(
      create: Gql.createReview,
      update: Gql.updateReview,
      input: {
        'ownerId': uid,
        'reviewId': review.id,
        'productId': review.productId,
        // AWSJSON 은 JSON "문자열"로 보내야 한다.
        'data': jsonEncode(review.toJson()),
      },
    );
  }

  Future<void> deleteReview(String uid, String reviewId) async {
    await _deleteIgnoringMissing(
      Gql.deleteReview,
      {'ownerId': uid, 'reviewId': reviewId},
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 회원 탈퇴
  // ─────────────────────────────────────────────────────────────

  /// 2단계 범위의 내 데이터를 모두 지운다. 프로필은 마지막에 지운다.
  Future<void> deleteAll(String uid) async {
    final profile = await _gql.query(Gql.getProfile, variables: {'ownerId': uid});
    final handle = (profile['getProfile'] as Map?)?['handleLower'] as String?;

    final tabs = await _listAll(Gql.listTabs, 'listWishTabs', uid);
    final products = await _listAll(Gql.listProducts, 'listWishProducts', uid);
    final reviews = await _listAll(Gql.listReviews, 'listReviews', uid);
    await _runLimited([
      for (final t in tabs)
        () => _deleteIgnoringMissing(
              Gql.deleteTab,
              {'ownerId': uid, 'tabId': t['tabId']},
            ),
      for (final p in products)
        () => _deleteIgnoringMissing(
              Gql.deleteProduct,
              {'ownerId': uid, 'productId': p['productId']},
            ),
      for (final r in reviews)
        () => _deleteIgnoringMissing(
              Gql.deleteReview,
              {'ownerId': uid, 'reviewId': r['reviewId']},
            ),
    ]);

    if (handle != null) await _deleteHandleIfMine(uid, handle);
    await _deleteIgnoringMissing(Gql.deletePrivateProfile, {'ownerId': uid});
    await _deleteIgnoringMissing(Gql.deleteProfile, {'ownerId': uid});
  }

  // ─────────────────────────────────────────────────────────────
  // 공통 도우미
  // ─────────────────────────────────────────────────────────────

  /// 만들기를 먼저 시도하고, 이미 있으면 수정한다.
  /// (AppSync 의 "만들기"는 같은 키가 있으면 거절하고, "수정"은 없으면 거절한다)
  Future<void> _upsert({
    required String create,
    required String update,
    required Map<String, dynamic> input,
  }) async {
    try {
      await _gql.mutate(create, variables: {'input': input});
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
      await _gql.mutate(update, variables: {'input': input});
    }
  }

  Future<void> _createOrIgnoreExisting(
    String create,
    Map<String, dynamic> input,
  ) async {
    try {
      await _gql.mutate(create, variables: {'input': input});
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
    }
  }

  Future<void> _deleteIgnoringMissing(
    String delete,
    Map<String, dynamic> key,
  ) async {
    try {
      await _gql.mutate(delete, variables: {'input': key});
    } on AwsDataException catch (e) {
      if (!e.isConditionalCheckFailed) rethrow;
    }
  }

  /// ownerId 로 목록 전체를 페이지를 넘겨 가며 읽는다.
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

  /// 요청을 한 번에 [_parallel] 개씩만 보낸다. (너무 많이 동시에 보내면 거절될 수 있음)
  Future<void> _runLimited(List<Future<void> Function()> jobs) async {
    for (var i = 0; i < jobs.length; i += _parallel) {
      final end = min(i + _parallel, jobs.length);
      await Future.wait([for (final job in jobs.sublist(i, end)) job()]);
    }
  }

  AppUser _userFrom(Map<String, dynamic> p, {required String email}) =>
      userFromProfileRow(p, email: email);

  /// AppSync Profile 행 → AppUser. 친구 목록(AwsSocialStore)도 같이 쓴다.
  /// 팔로워·팔로잉 수는 저장값이 아니라 Follow 표에서 세므로 여기선 0 이다.
  static AppUser userFromProfileRow(
    Map<String, dynamic> p, {
    String email = '',
  }) =>
      AppUser(
        uid: p['ownerId'] as String? ?? '',
        email: email,
        name: p['name'] as String? ?? '사용자',
        handle: p['handle'] as String? ?? '@user',
        avatarUrl: p['avatarUrl'] as String? ?? AvatarPresets.urls.first,
        followers: _int(p['followers']),
        following: _int(p['following']),
      );

  String _defaultAvatar(String handle) {
    final seed = handle.replaceFirst('@', '');
    if (seed.isEmpty) return AvatarPresets.urls.first;
    return AvatarPresets.urlForSeed(seed);
  }

  static String _emailLocal(String email) {
    final local = email.contains('@') ? email.split('@').first : '';
    final cleaned = local.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    return cleaned.length >= 3 ? cleaned : 'user';
  }

  static Set<String> _stringSet(Object? raw) =>
      (raw is List ? raw : const []).map((e) => e.toString()).toSet();

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;
  static int? _intOrNull(Object? v) => (v as num?)?.toInt();

  static Map<String, dynamic>? _jsonMap(Object? raw) => decodeAwsJson(raw);
}
