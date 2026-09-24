import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../models/models.dart';
import '../services/account_repository.dart';
import '../services/push_notification_service.dart';
import '../services/share_page_html.dart';
import '../theme/diary_theme.dart';
import '../utils/action_lock.dart';
import '../utils/tap_cooldown.dart';

class AppStore extends ChangeNotifier {
  static const _basketKey = 'basket_items';
  static const _sharedKey = 'shared_baskets';
  static const _notificationsEnabledKey = 'notifications_enabled';
  // Legacy per-type keys, read once to migrate into _notificationsEnabledKey.
  static const _legacyNotifyFollowKey = 'notify_follow';
  static const _legacyNotifyBasketKey = 'notify_basket';
  static const _reviewsKey = 'my_reviews';
  static const _hiddenFeedKey = 'hidden_feed_baskets';

  AppStore({
    AuthController? auth,
    AccountRepository? repository,
    bool backendConfigured = true,
    ActionLock? actionLock,
    TapCooldown? actionCooldown,
  }) : _auth = auth,
       _repo = repository ?? AccountRepository(),
       _backendConfigured = backendConfigured,
       _actionLock = actionLock ?? ActionLock(),
       _actionCooldown = actionCooldown ?? TapCooldown();

  /// 로그인 상태의 원본. (테스트에서는 null 일 수 있음)
  final AuthController? _auth;
  StreamSubscription<AuthUserInfo?>? _authSub;
  final AccountRepository _repo;
  /// AWS(Amplify) 연결이 준비됐는지. 테스트에서는 false 로 둔다.
  final bool _backendConfigured;
  final ActionLock _actionLock;
  final TapCooldown _actionCooldown;
  StreamSubscription<List<AppNotification>>? _notificationSub;
  StreamSubscription<List<SharedBasket>>? _receivedBasketSub;

  bool ready = false;
  /// AWS 연결이 준비돼 데이터를 불러올 수 있는지.
  bool backendReady = false;
  String? backendError;
  /// 앱 데이터가 로그인 사용자 기준으로 준비됐는지. 로그인 여부의 원본은 AuthController.
  bool isLoggedIn = false;

  /// In-app notification preference (MyPage → 알림 설정).
  bool notificationsEnabled = true;

  List<WishlistTab> tabs = [];
  List<Product> products = [];
  List<BasketItem> basket = [];
  List<Friend> friends = [];
  List<FriendWishlist> friendWishlists = [];
  List<AppUser> followerUsers = [];
  List<AppNotification> notifications = [];
  List<SharedBasket> receivedBaskets = [];
  List<ProductReview> myReviews = [];
  List<ProductReview> friendReviews = [];
  final Map<String, SharedBasket> sharedBaskets = {};

  /// Baskets the user X-ed out of the 내 친구 탭 feed. The profile doc is the
  /// source of truth; this is the local cache the UI reads, kept so nothing
  /// flashes back while the server copy loads.
  Set<String> _hiddenFeedIds = {};

  /// Hide / unhide taps the server has not confirmed yet (offline, or a failed
  /// write). Replayed on the next sync and layered over the server value so a
  /// local tap is never silently lost.
  Set<String> _pendingHideIds = {};
  Set<String> _pendingUnhideIds = {};

  String selectedTabId = 'all';
  int friendsTab = 0;
  String? pendingShareUrl;

  AppUser currentUser = AppUser(
    name: '게스트',
    handle: '@guest',
    avatarUrl: 'https://api.dicebear.com/7.x/thumbs/png?seed=guest',
  );

  Future<void> init() async {
    // 로그인/로그아웃 변화는 백엔드 준비 여부와 상관없이 항상 받는다.
    _authSub ??= _auth?.userChanges.listen(_onAuthUserChanged);
    backendReady = _backendConfigured;
    if (!backendReady) {
      backendError =
          'AWS 연결이 아직 안 됐어요. sandbox 를 실행해 amplify_outputs.dart 를 만들어 주세요.';
      ready = true;
      notifyListeners();
      return;
    }

    // 앱 시작 시 이미 로그인돼 있으면 바로 데이터를 불러오고,
    // 이후 로그인/로그아웃은 AuthController.userChanges 로 받는다.
    final user = _auth?.user;
    if (user != null) {
      await _hydrateSessionSafely(user);
    }

    await _loadLocalExtras();
    ready = true;
    notifyListeners();
  }

  Future<void> _onAuthUserChanged(AuthUserInfo? user) async {
    if (user == null) {
      await PushNotificationService.instance.unregister();
      await _clearSessionLocal();
    } else {
      await _hydrateSessionSafely(user);
      await _restoreBasketForUser();
    }
    notifyListeners();
  }

  /// 데이터 불러오기가 실패해도 로그인 자체는 막지 않는다.
  Future<void> _hydrateSessionSafely(AuthUserInfo user) async {
    try {
      await _hydrateSession(user);
    } catch (e) {
      debugPrint('AppStore: 데이터 불러오기 실패 (${e.runtimeType})');
      backendError = '데이터를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
      isLoggedIn = true;
    }
  }

  Future<void> _hydrateSession(AuthUserInfo fresh) async {
    await _repo.ensureProfile(
      uid: fresh.uid,
      email: fresh.email,
      name: fresh.signupName,
      handle: fresh.signupHandle,
    );
    final profile = await _repo.loadProfile(fresh.uid);
    if (profile != null) {
      currentUser = profile;
    }
    // 내 데이터 (AWS) — 실패하면 로그인 후 데이터 준비 전체를 실패로 본다.
    tabs = await _repo.loadTabs(fresh.uid);
    products = await _repo.loadProducts(fresh.uid);

    // 친구·팔로우 — 불러오기가 실패해도 내 데이터 화면은 쓸 수 있게 한다.
    try {
      final following = (await _repo.followingIds(fresh.uid)).toSet();
      friends =
          await _repo.loadDirectory(myUid: fresh.uid, following: following);
      friendWishlists = await _repo.loadFriendWishlists(friends);
      followerUsers =
          await _repo.loadUsers(await _repo.followerIds(fresh.uid));
      currentUser = currentUser.copyWith(
        following: following.length,
        followers: followerUsers.length,
      );
    } catch (e) {
      debugPrint('AppStore: 친구 정보 불러오기 실패 (${e.runtimeType})');
    }
    await _loadInboxSafely(fresh.uid);
    await _loadReviewsSafely(fresh.uid);
    _syncFriendCounts();
    isLoggedIn = true;
    selectedTabId = 'all';
    await _reloadNotificationPrefs();
    _watchInbox(fresh.uid);
    unawaited(PushNotificationService.instance.register(fresh.uid, _repo));
  }

  Future<void> _reloadNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    notificationsEnabled = _readNotificationsEnabled(prefs, uid ?? 'guest');
  }

  /// Reads the single notifications toggle, migrating from the old
  /// per-type (notify_follow / notify_basket) keys the first time: enabled
  /// unless both legacy flags were stored as false.
  bool _readNotificationsEnabled(SharedPreferences prefs, String keySuffix) {
    final stored = prefs.getBool('${_notificationsEnabledKey}_$keySuffix');
    if (stored != null) return stored;
    final legacyFollow =
        prefs.getBool('${_legacyNotifyFollowKey}_$keySuffix') ?? true;
    final legacyBasket =
        prefs.getBool('${_legacyNotifyBasketKey}_$keySuffix') ?? true;
    return legacyFollow || legacyBasket;
  }

  /// Notifications / received baskets load independently of the rest.
  /// Never block login if those collections are still denied.
  Future<void> _loadInboxSafely(String userId) async {
    try {
      notifications = await _repo.loadNotifications(userId);
    } catch (_) {
      notifications = [];
    }
    try {
      receivedBaskets = await _repo.loadReceivedBaskets(userId);
    } catch (_) {
      receivedBaskets = [];
    }
    try {
      final sent = await _repo.loadSentBaskets(userId);
      sharedBaskets
        ..clear()
        ..addEntries(sent.map((b) => MapEntry(b.id, b)));
      await _persistShared();
    } catch (_) {}
    await _syncHiddenFeed(userId);
  }

  /// Local cache first (so nothing flashes), then let the profile doc win:
  /// an id the server does not list is dropped even if this device still has
  /// it cached, which is what makes an unhide on another device stick.
  ///
  /// Only this device's unconfirmed taps survive that — they are replayed and
  /// re-applied on top. Offline the server read throws and the cache is kept
  /// untouched.
  Future<void> _syncHiddenFeed(String userId) async {
    await _restoreHiddenFeedLocal();
    final Set<String> remote;
    try {
      remote = await _repo.loadHiddenFeedBaskets(userId);
    } catch (_) {
      return;
    }

    // Snapshot the queues before flushing so a tap made mid-flight is not
    // dropped from the merge below.
    final hideQueue = {..._pendingHideIds};
    final unhideQueue = {..._pendingUnhideIds};
    try {
      await _repo.hideFeedBaskets(userId, hideQueue);
      _pendingHideIds.removeAll(hideQueue);
    } catch (_) {}
    try {
      await _repo.unhideFeedBaskets(userId, unhideQueue);
      _pendingUnhideIds.removeAll(unhideQueue);
    } catch (_) {}

    _hiddenFeedIds = {...remote, ...hideQueue}..removeAll(unhideQueue);
    await _persistHiddenFeed();
    notifyListeners();
  }

  Future<void> _loadReviewsSafely(String userId) async {
    try {
      myReviews = await _repo.loadReviews(userId);
    } catch (_) {
      await _restoreLocalReviews();
    }
    if (myReviews.isEmpty) {
      await _restoreLocalReviews();
    }
    try {
      friendReviews = await _repo.loadFriendReviews(friends);
    } catch (_) {
      friendReviews = [];
    }
  }

  Future<void> _clearSessionLocal() async {
    _stopInboxWatch();
    isLoggedIn = false;
    tabs = [];
    products = [];
    basket = [];
    friends = [];
    friendWishlists = [];
    followerUsers = [];
    notifications = [];
    receivedBaskets = [];
    myReviews = [];
    friendReviews = [];
    _hiddenFeedIds = {};
    _pendingHideIds = {};
    _pendingUnhideIds = {};
    sharedBaskets.clear();
    currentUser = AppUser(
      name: '게스트',
      handle: '@guest',
      avatarUrl: 'https://api.dicebear.com/7.x/thumbs/png?seed=guest',
    );
    selectedTabId = 'all';
    friendsTab = 0;
  }

  // ── 로그인 관련: 실제 처리는 AuthController 가 한다 ─────────────────
  // 마이페이지 등 기존 화면이 그대로 쓸 수 있도록 이름을 유지해 전달만 한다.

  /// 로그인 화면이 쓰는 앱 데이터 연결 지점. main.dart 에서 auth.hooks 로 넣는다.
  AuthDataHooks get authHooks => AuthDataHooks(
        isHandleAvailable: _repo.isHandleAvailable,
        findMaskedEmailByHandle: _repo.findMaskedEmailByHandle,
        deleteMyData: _repo.deleteUserData,
      );

  Future<void> logout() async {
    await PushNotificationService.instance.unregister();
    final auth = _auth;
    if (auth != null) {
      await auth.logout(); // userChanges(null) → _clearSessionLocal
    } else {
      await _clearSessionLocal();
      notifyListeners();
    }
  }

  /// 비밀번호 확인 → 내 데이터 삭제 → 계정 삭제 (순서는 AuthController 가 보장).
  Future<void> deleteAccount({required String password}) async {
    final auth = _auth;
    if (auth == null) throw Exception('로그인 기능이 연결되지 않았어요.');
    await PushNotificationService.instance.unregister();
    await auth.deleteAccount(password: password);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final auth = _auth;
    if (auth == null) throw Exception('로그인 기능이 연결되지 않았어요.');
    await auth.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopInboxWatch();
    super.dispose();
  }

  void _ensureBackend() {
    if (!backendReady) {
      throw Exception(
        'AWS 연결이 아직 안 됐어요. sandbox 를 실행해 amplify_outputs.dart 를 만들어 주세요.',
      );
    }
  }

  String? get uid =>
      currentUser.uid.isNotEmpty ? currentUser.uid : _auth?.uid;

  List<Product> get displayedProducts {
    if (selectedTabId == 'all') return products;
    return products.where((p) => p.listId == selectedTabId).toList();
  }

  WishlistTab get selectedTab =>
      tabs.firstWhere((t) => t.id == selectedTabId, orElse: () => tabs.first);

  List<WishlistTab> get customTabs => tabs.where((t) => t.id != 'all').toList();

  Color tabColor(WishlistTab tab) {
    const map = {'all': DiaryColors.fileCream};
    if (tab.colorHex != null && tab.colorHex!.isNotEmpty) {
      final hex = tab.colorHex!.replaceFirst('#', '');
      try {
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    if (map.containsKey(tab.id)) return map[tab.id]!;
    return DiaryColors.fileCream;
  }

  Color nextFileColor() {
    final used = <int>{
      for (final t in tabs.where((t) => t.id != 'all')) tabColor(t).toARGB32(),
    };
    final unused = DiaryColors.fileColors.where(
      (c) => !used.contains(c.toARGB32()),
    );
    final pool = unused.isNotEmpty
        ? unused.toList()
        : DiaryColors.fileColors.toList();
    return pool[Random().nextInt(pool.length)];
  }

  Future<void> reorderTabs(int oldIndex, int newIndex) async {
    final allTab = tabs.firstWhere((t) => t.id == 'all');
    final rest = tabs.where((t) => t.id != 'all').toList();
    if (oldIndex < 0 || oldIndex >= rest.length) return;
    final target = newIndex;
    if (target < 0 || target >= rest.length) return;
    final item = rest.removeAt(oldIndex);
    rest.insert(target, item);
    tabs = [allTab, ...rest];
    await _persistTabs();
    notifyListeners();
  }

  int countFor(WishlistTab tab) {
    if (tab.id == 'all') return products.length;
    return products.where((p) => p.listId == tab.id).length;
  }

  void selectTab(String id) {
    selectedTabId = id;
    notifyListeners();
  }

  void selectFriendsTab(int index) {
    if (friendsTab == index) return;
    friendsTab = index;
    notifyListeners();
  }

  Future<void> _persistTabs() async {
    final id = uid;
    if (id == null) return;
    await _repo.saveTabs(id, tabs);
  }

  /// Returns false when another list is already being created.
  Future<bool> addTab(String name, {bool isPublic = false}) async {
    final created = await _withLock('addTab', () async {
      final color = nextFileColor();
      final hex =
          '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      final tab = WishlistTab(
        id: 'list-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        isPublic: isPublic,
        colorHex: hex,
      );
      tabs = [...tabs, tab];
      selectedTabId = tab.id;
      await _persistTabs();
      notifyListeners();
      return true;
    });
    return created ?? false;
  }

  Future<void> renameTab(String id, String name) async {
    tabs = tabs.map((t) => t.id == id ? t.copyWith(name: name) : t).toList();
    await _persistTabs();
    notifyListeners();
  }

  Future<void> deleteTab(String id) async {
    if (id == 'all') return;
    tabs = tabs.where((t) => t.id != id).toList();
    if (selectedTabId == id) selectedTabId = 'all';
    final userId = uid;
    if (userId != null) {
      await _repo.deleteTabDoc(userId, id);
      await _persistTabs();
    }
    notifyListeners();
  }

  Future<void> toggleTabPublic(String id) async {
    tabs = tabs
        .map((t) => t.id == id ? t.copyWith(isPublic: !t.isPublic) : t)
        .toList();
    final isPublic =
        tabs.where((t) => t.id == id).firstOrNull?.isPublic ?? false;
    products = [
      for (final p in products)
        p.listId == id ? p.copyWith(isPublic: isPublic) : p,
    ];
    await _persistTabs();
    notifyListeners();
  }

  Future<void> removeProduct(int id) async {
    products = products.where((p) => p.id != id).toList();
    basket = basket.where((b) => b.product.id != id).toList();
    final userId = uid;
    if (userId != null) {
      await _repo.deleteProduct(userId, id);
    }
    await _persistBasket();
    notifyListeners();
  }

  /// Optimistically moves [id] into [listId], persists to the backend, and
  /// reverts the in-memory state (rethrowing) if the write fails — callers
  /// are expected to surface the error rather than let it fail silently.
  Future<void> moveProduct(int id, String listId) async {
    final previous = products;
    final product = productById(id);
    if (product == null || product.listId == listId) return;
    final updated = product.copyWith(
      listId: listId,
      isPublic: _isListPublic(listId),
    );
    products = [for (final p in products) p.id == id ? updated : p];
    notifyListeners();
    final userId = uid;
    if (userId == null) return;
    try {
      await _repo.upsertProduct(userId, updated);
    } catch (_) {
      products = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateMemo(int id, String memo) async {
    products = products
        .map((p) => p.id == id ? p.copyWith(memo: memo) : p)
        .toList();
    final userId = uid;
    final product = productById(id);
    if (userId != null && product != null) {
      await _repo.upsertProduct(userId, product);
    }
    notifyListeners();
  }

  Future<void> addToBasket(Product product) async {
    if (basket.any((b) => b.product.id == product.id)) return;
    basket = [...basket, BasketItem(product: product)];
    await _persistBasket();
    notifyListeners();
  }

  /// Add several products at once — persists and notifies a single time.
  Future<void> addManyToBasket(Iterable<Product> products) async {
    final existing = basket.map((b) => b.product.id).toSet();
    final added = <BasketItem>[];
    for (final product in products) {
      if (!existing.add(product.id)) continue;
      added.add(BasketItem(product: product));
    }
    if (added.isEmpty) return;
    basket = [...basket, ...added];
    await _persistBasket();
    notifyListeners();
  }

  Future<void> toggleBasketSelected(int id) async {
    basket = basket
        .map(
          (b) => b.product.id == id ? b.copyWith(isSelected: !b.isSelected) : b,
        )
        .toList();
    await _persistBasket();
    notifyListeners();
  }

  Future<void> removeFromBasket(int id) async {
    basket = basket.where((b) => b.product.id != id).toList();
    await _persistBasket();
    notifyListeners();
  }

  /// Returns null when a save for the same product is already in flight.
  Future<Product?> addParsedProduct(
    ParsedProductInfo info, {
    required String listId,
    String memo = '',
  }) async {
    final lockKey =
        'addParsedProduct:${info.productUrl.isEmpty ? info.name : info.productUrl}';
    return _withLock(lockKey, () async {
      final trimmedMemo = memo.trim();
      final id = (products.map((e) => e.id).fold<int>(0, max)) + 1;
      final product = Product(
        id: id == 0 ? DateTime.now().millisecondsSinceEpoch : id,
        listId: listId,
        name: info.name,
        price: info.price,
        image: info.image,
        platform: info.platform,
        originalPrice: info.originalPrice,
        discount: info.discount,
        productUrl: info.productUrl,
        memo: trimmedMemo.isEmpty ? null : trimmedMemo,
        isPublic: _isListPublic(listId),
      );
      products = [...products, product];
      final userId = uid;
      if (userId != null) {
        await _repo.upsertProduct(userId, product);
      }
      notifyListeners();
      return product;
    });
  }

  void setPendingShareUrl(String? url) {
    pendingShareUrl = url;
    notifyListeners();
  }

  Product? productById(int id) {
    return products.where((p) => p.id == id).firstOrNull;
  }

  bool _isListPublic(String listId) {
    return tabs.where((t) => t.id == listId).firstOrNull?.isPublic ?? false;
  }

  Friend? friendById(String id) => friends.where((f) => f.id == id).firstOrNull;

  List<FriendWishlist> wishlistsForFriend(String friendId) =>
      friendWishlists.where((w) => w.friendId == friendId).toList();

  FriendWishlist? friendWishlistById(String id) =>
      friendWishlists.where((w) => w.id == id).firstOrNull;

  SharedBasket? sharedBasketById(String id) {
    final local = sharedBaskets[id];
    if (local != null) return local;
    return receivedBaskets
        .where((b) => b.id == id || b.threadId == id || b.commentThreadId == id)
        .firstOrNull;
  }

  int get unreadNotificationCount =>
      visibleNotifications.where((n) => !n.read).length;

  /// Inbox rows. Review/list notifications aren't part of the inbox;
  /// everything else is always shown — notificationsEnabled only gates the
  /// OS banner (see _watchInbox), not the in-app list.
  List<AppNotification> get visibleNotifications => notifications.where((n) {
    return n.type != AppNotificationType.review &&
        n.type != AppNotificationType.list;
  }).toList();

  List<FriendSalkamalka> get friendSalkamalkaGroups {
    final byFriend = <String, List<SharedBasket>>{};
    for (final b in receivedBaskets) {
      final key = b.fromUid.isNotEmpty ? b.fromUid : b.ownerName;
      byFriend.putIfAbsent(key, () => []).add(b);
    }
    final groups = byFriend.entries.map((e) {
      final baskets = List<SharedBasket>.from(e.value)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final first = baskets.first;
      return FriendSalkamalka(
        friendId: first.fromUid,
        friendName: first.ownerName,
        friendHandle: first.fromHandle,
        friendAvatar: first.fromAvatar.isNotEmpty
            ? first.fromAvatar
            : 'https://api.dicebear.com/7.x/thumbs/png?seed=${Uri.encodeComponent(first.ownerName)}',
        baskets: baskets,
      );
    }).toList();
    groups.sort(
      (a, b) => b.baskets.first.createdAt.compareTo(a.baskets.first.createdAt),
    );
    return groups;
  }

  FriendSalkamalka? friendSalkamalkaByFriendId(String friendId) =>
      friendSalkamalkaGroups.where((g) => g.friendId == friendId).firstOrNull;

  /// Feed behind 내 친구 탭 > 살까말까. Display-level filtering only — nothing is
  /// dropped from [sentBaskets], which stays the full archive for 마이페이지.
  List<SalkamalkaFeedEntry> get salkamalkaFeed {
    final myUid = uid ?? '';
    final out = <SalkamalkaFeedEntry>[
      for (final b in receivedBaskets)
        if (!_isSentByMe(b, myUid))
          SalkamalkaFeedEntry(basket: b, isMine: false),
      // Link / KakaoTalk shares never went to an app friend, so they do not
      // belong in the friends feed.
      for (final b in sentBaskets)
        if (b.sharedToFriends && _isSentByMe(b, myUid))
          SalkamalkaFeedEntry(basket: b, isMine: true),
    ];
    // Prefer the sent copy when the same id somehow appears in both.
    final byId = <String, SalkamalkaFeedEntry>{};
    for (final e in out) {
      if (_hiddenFeedIds.contains(e.basket.id)) continue;
      if (_hiddenFeedIds.contains(e.basket.commentThreadId)) continue;
      byId[e.basket.id] = e;
    }
    return byId.values.toList()
      ..sort((a, b) => b.basket.sharedAt.compareTo(a.basket.sharedAt));
  }

  bool _isSentByMe(SharedBasket basket, String myUid) {
    if (myUid.isEmpty) return false;
    if (basket.fromUid.isNotEmpty) return basket.fromUid == myUid;
    return sharedBaskets.containsKey(basket.id);
  }

  bool isHiddenFromSalkamalkaFeed(String id) => _hiddenFeedIds.contains(id);

  /// Hides one entry from the friends feed only. The basket itself is kept, so
  /// 마이페이지 > 내가 보낸 살까말까 still lists it.
  Future<void> hideFromSalkamalkaFeed(String id) async {
    if (!_hiddenFeedIds.add(id)) return;
    _pendingUnhideIds.remove(id);
    _pendingHideIds.add(id);
    notifyListeners();
    await _persistHiddenFeed();
    final userId = uid;
    if (userId == null) return;
    try {
      await _repo.hideFeedBaskets(userId, [id]);
      _pendingHideIds.remove(id);
      await _persistHiddenFeed();
    } catch (_) {
      // Stays queued and is replayed on the next sync.
    }
  }

  /// Brings an entry back into the friends feed. Re-sending a basket counts as
  /// wanting to see it again, so the earlier X is undone.
  Future<void> unhideFromSalkamalkaFeed(String id) async {
    if (!_hiddenFeedIds.remove(id)) return;
    _pendingHideIds.remove(id);
    _pendingUnhideIds.add(id);
    notifyListeners();
    await _persistHiddenFeed();
    final userId = uid;
    if (userId == null) return;
    try {
      await _repo.unhideFeedBaskets(userId, [id]);
      _pendingUnhideIds.remove(id);
      await _persistHiddenFeed();
    } catch (_) {}
  }

  Future<void> _persistHiddenFeed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${_hiddenFeedKey}_${uid ?? 'guest'}',
      jsonEncode({
        'hidden': _hiddenFeedIds.toList(),
        'pendingHide': _pendingHideIds.toList(),
        'pendingUnhide': _pendingUnhideIds.toList(),
      }),
    );
  }

  Future<void> _restoreHiddenFeedLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_hiddenFeedKey}_${uid ?? 'guest'}');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      // Caches written before the pending queues existed were a bare id list.
      if (decoded is List) {
        _hiddenFeedIds = {..._hiddenFeedIds, ..._asIdSet(decoded)};
        return;
      }
      final map = Map<String, dynamic>.from(decoded as Map);
      _hiddenFeedIds = {..._hiddenFeedIds, ..._asIdSet(map['hidden'])};
      _pendingHideIds = {..._pendingHideIds, ..._asIdSet(map['pendingHide'])};
      _pendingUnhideIds = {
        ..._pendingUnhideIds,
        ..._asIdSet(map['pendingUnhide']),
      };
    } catch (_) {}
  }

  Set<String> _asIdSet(dynamic raw) =>
      (raw as List? ?? const []).map((e) => e.toString()).toSet();

  Future<List<AppUser>> loadFollowers() async {
    final id = uid;
    if (id == null) return [];
    final ids = await _repo.followerIds(id);
    followerUsers = await _repo.loadUsers(ids);
    notifyListeners();
    return followerUsers;
  }

  Future<List<AppUser>> loadFollowingUsers() async {
    final id = uid;
    if (id == null) return [];
    final ids = await _repo.followingIds(id);
    return _repo.loadUsers(ids);
  }

  Future<void> refreshFriends() async {
    final userId = uid;
    if (userId == null) return;
    final following = (await _repo.followingIds(userId)).toSet();
    friends = await _repo.loadDirectory(myUid: userId, following: following);
    friendWishlists = await _repo.loadFriendWishlists(friends);
    followerUsers = await _repo.loadUsers(await _repo.followerIds(userId));
    await _loadInboxSafely(userId);
    await _loadReviewsSafely(userId);
    _syncFriendCounts();
    final profile = await _repo.loadProfile(userId);
    if (profile != null) {
      currentUser = profile;
    } else {
      currentUser = currentUser.copyWith(
        following: following.length,
        followers: followerUsers.length,
      );
    }
    notifyListeners();
  }

  Future<void> refreshNotifications() async {
    final userId = uid;
    if (userId == null) return;
    try {
      notifications = await _repo.loadNotifications(userId);
    } catch (_) {
      notifications = [];
    }
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    final userId = uid;
    if (userId == null) return;
    final unread = notifications
        .where((n) => !n.read)
        .map((n) => n.id)
        .toList();
    if (unread.isEmpty) return;
    try {
      await _repo.markNotificationsRead(userId, unread);
      notifications = [for (final n in notifications) n.copyWith(read: true)];
      notifyListeners();
    } catch (_) {}
  }

  /// Returns false when ignored (not signed in, unknown friend, or 2s cooldown).
  Future<bool> toggleFollow(String friendId) async {
    final userId = uid;
    if (userId == null) return false;
    final idx = friends.indexWhere((f) => f.id == friendId);
    if (idx < 0) return false;
    if (!_actionCooldown.begin('follow:$friendId')) return false;
    try {
      final wasFollowing = friends[idx].isFollowing;
      final next = !wasFollowing;
      await _repo.setFollowing(
        myUid: userId,
        targetUid: friendId,
        follow: next,
        actor: next ? currentUser.copyWith(uid: userId) : null,
      );
      friends = [
        for (var i = 0; i < friends.length; i++)
          if (i == idx) friends[i].copyWith(isFollowing: next) else friends[i],
      ];
      currentUser = currentUser.copyWith(
        following: friends.where((f) => f.isFollowing).length,
      );
      friendWishlists = await _repo.loadFriendWishlists(friends);
      try {
        friendReviews = await _repo.loadFriendReviews(friends);
      } catch (_) {}
      _syncFriendCounts();
      notifyListeners();
      return true;
    } finally {
      _actionCooldown.end('follow:$friendId');
    }
  }

  Future<void> removeFollower(String followerUid) async {
    final userId = uid;
    if (userId == null) {
      throw Exception('로그인된 계정이 없어요.');
    }
    await _repo.removeFollower(myUid: userId, followerUid: followerUid);
    followerUsers = followerUsers.where((u) => u.uid != followerUid).toList();
    currentUser = currentUser.copyWith(followers: followerUsers.length);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    await _persistNotificationPrefs();
    notifyListeners();
  }

  void _watchInbox(String userId) {
    _stopInboxWatch();
    var primed = false;
    final seen = <String>{};
    _notificationSub = _repo.watchNotifications(userId).listen((list) {
      if (primed) {
        for (final n in list) {
          if (!seen.contains(n.id) &&
              n.type != AppNotificationType.review &&
              n.type != AppNotificationType.list) {
            if (notificationsEnabled) {
              unawaited(PushNotificationService.instance.showInboxBanner(n));
            }
          }
        }
      }
      seen
        ..clear()
        ..addAll(list.map((n) => n.id));
      primed = true;
      notifications = list;
      notifyListeners();
    }, onError: (_) {});
    _receivedBasketSub = _repo.watchReceivedBaskets(userId).listen((list) {
      receivedBaskets = list;
      notifyListeners();
    }, onError: (_) {});
  }

  void _stopInboxWatch() {
    _notificationSub?.cancel();
    _notificationSub = null;
    _receivedBasketSub?.cancel();
    _receivedBasketSub = null;
  }

  void _syncFriendCounts() {
    friends = friends.map((f) {
      final lists = friendWishlists.where((w) => w.friendId == f.id).toList();
      final items = lists.fold<int>(0, (sum, w) => sum + w.items.length);
      return f.copyWith(wishlistCount: lists.length, itemCount: items);
    }).toList();
  }

  Future<void> updateProfile({
    String? name,
    String? handle,
    String? avatarUrl,
  }) async {
    final previousHandle = currentUser.handle;
    var nextHandle = handle?.trim() ?? currentUser.handle;
    if (nextHandle.isEmpty) {
      throw Exception('아이디를 입력해 주세요.');
    }
    if (!nextHandle.startsWith('@')) {
      nextHandle = '@$nextHandle';
    }
    final userId = uid;
    if (userId == null) {
      throw Exception('로그인된 계정이 없어요.');
    }
    await _repo.assertHandleAvailable(nextHandle, exceptUid: userId);
    final nextUser = currentUser.copyWith(
      name: name?.trim().isNotEmpty == true ? name!.trim() : null,
      handle: nextHandle,
      avatarUrl: avatarUrl?.trim().isNotEmpty == true
          ? avatarUrl!.trim()
          : null,
    );
    await _repo.updateProfile(userId, nextUser, previousHandle: previousHandle);
    currentUser = nextUser;
    notifyListeners();
  }

  /// Uploads [file] to Storage and returns the public download URL.
  Future<String> uploadAvatarFile(File file) async {
    _ensureBackend();
    final userId = uid;
    if (userId == null) {
      throw Exception('로그인된 계정이 없어요.');
    }
    return _repo.uploadAvatarFile(userId, file);
  }

  Future<SharedBasket> createSharedBasketFromSelection({
    String memo = '',
  }) async {
    final selected = basket
        .where((b) => b.isSelected)
        .map((b) => b.product)
        .toList();
    if (selected.isEmpty) {
      throw Exception('공유할 상품을 선택해 주세요.');
    }
    return rememberSentBasket(
      items: selected,
      title: '살까말까 공유',
      channels: const [SharedChannel.friends],
      memo: memo,
    );
  }

  List<SharedBasket> get sentBaskets {
    final list = sharedBaskets.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<SharedBasket> rememberSentBasket({
    required List<Product> items,
    String title = '살까말까 공유',
    List<String> recipientUids = const [],
    List<String> recipientNames = const [],
    List<String> channels = const [],
    String? existingId,
    bool touchSharedAt = false,
    String memo = '',
  }) async {
    final now = DateTime.now();
    final id = existingId ?? 'sb-${now.millisecondsSinceEpoch}';
    final existing = sharedBaskets[id];
    final mergedUids = {...?existing?.recipientUids, ...recipientUids}.toList();
    final mergedNames = {
      ...?existing?.recipientNames,
      ...recipientNames,
    }.where((n) => n.isNotEmpty).toList();
    // Channels accumulate: a link share re-sent to friends counts as both.
    final mergedChannels = {...?existing?.channels, ...channels}.toList();
    final shared = SharedBasket(
      id: id,
      title: title,
      ownerName: currentUser.name,
      fromUid: uid ?? currentUser.uid,
      fromHandle: currentUser.handle,
      fromAvatar: currentUser.avatarUrl,
      items: items,
      createdAt: existing?.createdAt ?? now,
      recipientUids: mergedUids,
      recipientNames: mergedNames,
      channels: mergedChannels,
      // Re-sending bumps the basket back to the top of the friends feed;
      // createdAt stays put so 마이페이지 keeps the original date.
      lastSharedAt: touchSharedAt ? now : existing?.lastSharedAt,
      publicPageId: existing?.publicPageId,
      publicUrl: existing?.publicUrl,
      publicUrlExpiresAt: existing?.publicUrlExpiresAt,
      memo: memo.isNotEmpty ? memo : (existing?.memo ?? ''),
      threadId: existing?.threadId.isNotEmpty == true ? existing!.threadId : id,
    );
    sharedBaskets[id] = shared;
    await _persistShared();
    final userId = uid;
    if (userId != null) {
      try {
        await _repo.upsertSentBasket(userId, shared);
      } catch (_) {}
    }
    notifyListeners();
    return shared;
  }

  /// Returns false when a send for the same basket is already in flight.
  Future<bool> sendBasketToFriends(
    List<String> friendIds, {
    String memo = '',
  }) async {
    final selected = basket
        .where((b) => b.isSelected)
        .map((b) => b.product)
        .toList();
    if (selected.isEmpty) {
      throw Exception('공유할 상품을 선택해 주세요.');
    }
    return resendBasketToFriends(
      items: selected,
      friendIds: friendIds,
      memo: memo,
    );
  }

  /// Returns false when a send for the same basket is already in flight.
  Future<bool> resendBasketToFriends({
    required List<Product> items,
    required List<String> friendIds,
    String? existingId,
    String memo = '',
  }) async {
    if (items.isEmpty) {
      throw Exception('공유할 상품을 선택해 주세요.');
    }
    if (friendIds.isEmpty) {
      throw Exception('보낼 친구를 선택해 주세요.');
    }
    final sent = await _withLock('sendBasket:${existingId ?? 'new'}', () async {
      _ensureBackend();
      final userId = uid;
      if (userId == null) {
        throw Exception('로그인된 계정이 없어요.');
      }
      final existingBasket = existingId == null
          ? null
          : sharedBaskets[existingId];
      final threadId = existingBasket?.commentThreadId.isNotEmpty == true
          ? existingBasket!.commentThreadId
          : (existingId ?? 'sb-${DateTime.now().millisecondsSinceEpoch}');
      await _repo.sendBasketToFriends(
        from: currentUser.copyWith(uid: userId),
        recipientUids: friendIds,
        items: items,
        threadId: threadId,
        memo: memo,
      );
      final names = [
        for (final id in friendIds) friendById(id)?.name ?? '',
      ].where((n) => n.isNotEmpty).toList();
      final shared = await rememberSentBasket(
        items: items,
        title: '${currentUser.name}의 살까말까',
        recipientUids: friendIds,
        recipientNames: names,
        channels: const [SharedChannel.friends],
        existingId: threadId,
        touchSharedAt: true,
        memo: memo,
      );
      // Re-sending a basket that was X-ed out of the friends feed brings it back.
      // Covers both re-used ids (마이페이지 > 다시 보내기) and freshly minted ones.
      await unhideFromSalkamalkaFeed(shared.id);
      return true;
    });
    return sent ?? false;
  }

  Stream<List<BasketComment>> watchBasketComments(String threadId) {
    if (threadId.isEmpty || !_backendConfigured || uid == null) {
      return Stream.value(const []);
    }
    return _repo.watchBasketComments(threadId);
  }

  /// Returns false when a comment on this thread is already being posted.
  Future<bool> postBasketComment({
    required SharedBasket basket,
    required String text,
    String parentId = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('댓글을 입력해 주세요.');
    }
    final threadId = basket.commentThreadId;
    if (threadId.isEmpty) {
      throw Exception('이 살까말까에는 댓글을 달 수 없어요.');
    }
    final posted = await _withLock('comment:$threadId', () async {
      _ensureBackend();
      final userId = uid;
      if (userId == null) {
        throw Exception('로그인된 계정이 없어요.');
      }
      final ownerUid = basket.fromUid.isNotEmpty ? basket.fromUid : userId;
      await _repo.addBasketComment(
        threadId: threadId,
        from: currentUser.copyWith(uid: userId),
        text: trimmed,
        parentId: parentId,
        ownerUid: ownerUid,
        participantUids: {ownerUid, userId, ...basket.recipientUids}.toList(),
        memo: basket.memo,
      );
      return true;
    });
    return posted ?? false;
  }

  /// Returns false when this comment is already being edited.
  Future<bool> updateBasketComment({
    required SharedBasket basket,
    required BasketComment comment,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('댓글을 입력해 주세요.');
    }
    final threadId = basket.commentThreadId;
    if (threadId.isEmpty) {
      throw Exception('이 살까말까에는 댓글을 달 수 없어요.');
    }
    final userId = uid;
    if (userId == null) {
      throw Exception('로그인된 계정이 없어요.');
    }
    if (comment.authorUid != userId) {
      throw Exception('내 댓글만 수정할 수 있어요.');
    }
    final updated = await _withLock('comment-edit:${comment.id}', () async {
      _ensureBackend();
      await _repo.updateBasketComment(
        threadId: threadId,
        commentId: comment.id,
        authorUid: userId,
        text: trimmed,
      );
      return true;
    });
    return updated ?? false;
  }

  /// Returns false when this comment is already being deleted.
  Future<bool> deleteBasketComment({
    required SharedBasket basket,
    required BasketComment comment,
  }) async {
    final threadId = basket.commentThreadId;
    if (threadId.isEmpty) {
      throw Exception('이 살까말까에는 댓글을 달 수 없어요.');
    }
    final userId = uid;
    if (userId == null) {
      throw Exception('로그인된 계정이 없어요.');
    }
    if (comment.authorUid != userId) {
      throw Exception('내 댓글만 삭제할 수 있어요.');
    }
    final deleted = await _withLock('comment-delete:${comment.id}', () async {
      _ensureBackend();
      await _repo.deleteBasketComment(
        threadId: threadId,
        commentId: comment.id,
        authorUid: userId,
      );
      return true;
    });
    return deleted ?? false;
  }

  /// Hosts an HTML snapshot of [basket] in Storage and returns a public URL.
  /// Re-publishing the same basket overwrites the page and restarts the 28-day
  /// clock so an actively re-shared link stays alive.
  Future<String> publishSharePage(SharedBasket basket) async {
    _ensureBackend();
    final userId = uid;
    if (userId == null || !isLoggedIn) {
      throw Exception('로그인하면 링크로 공유할 수 있어요.');
    }
    final pageId =
        (basket.publicPageId != null && basket.publicPageId!.isNotEmpty)
        ? basket.publicPageId!
        : const Uuid().v4();
    final expiresAt = DateTime.now().add(kSharePageTtl);
    final html = buildSharePageHtml(basket: basket, expiresAt: expiresAt);
    final url = await _repo.uploadSharePage(
      uid: userId,
      pageId: pageId,
      basketId: basket.id,
      html: html,
      expiresAt: expiresAt,
    );
    final updated = basket.copyWith(
      publicPageId: pageId,
      publicUrl: url,
      publicUrlExpiresAt: expiresAt,
      channels: {...basket.channels, SharedChannel.link}.toList(),
      lastSharedAt: DateTime.now(),
    );
    sharedBaskets[basket.id] = updated;
    await _persistShared();
    try {
      await _repo.upsertSentBasket(userId, updated);
    } catch (_) {}
    notifyListeners();
    return url;
  }

  String shareUrlFor(SharedBasket basket) =>
      basket.publicUrl ?? 'https://wishlist.app/shared/${basket.id}';

  Future<void> _persistShared() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sharedKey);
    await prefs.setString(
      '${_sharedKey}_${uid ?? 'guest'}',
      jsonEncode(sharedBaskets.values.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _persistBasket() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_basketKey}_${uid ?? 'guest'}';
    await prefs.setString(
      key,
      jsonEncode(basket.map((e) => e.product.id).toList()),
    );
  }

  Future<void> _restoreBasketForUser() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_basketKey}_${uid ?? 'guest'}';
    final basketRaw = prefs.getString(key);
    if (basketRaw == null) {
      basket = [];
      return;
    }
    final ids = (jsonDecode(basketRaw) as List).cast<int>();
    basket = ids
        .map((id) {
          final p = products.where((e) => e.id == id).firstOrNull;
          return p == null ? null : BasketItem(product: p);
        })
        .whereType<BasketItem>()
        .toList();
  }

  Future<void> _loadLocalExtras() async {
    final prefs = await SharedPreferences.getInstance();
    notificationsEnabled = _readNotificationsEnabled(prefs, uid ?? 'guest');
    if (sharedBaskets.isEmpty) {
      final sharedRaw = prefs.getString('${_sharedKey}_${uid ?? 'guest'}');
      if (sharedRaw != null) {
        final list = jsonDecode(sharedRaw) as List;
        for (final e in list) {
          final map = Map<String, dynamic>.from(e as Map);
          final basket = SharedBasket.fromJson(map);
          if (uid != null &&
              basket.fromUid.isNotEmpty &&
              basket.fromUid != uid) {
            continue;
          }
          sharedBaskets[basket.id] = basket;
        }
      }
    }
    await _restoreHiddenFeedLocal();
  }

  Future<void> _persistNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final keySuffix = uid ?? 'guest';
    await prefs.setBool(
      '${_notificationsEnabledKey}_$keySuffix',
      notificationsEnabled,
    );
  }

  /// Resolves a product card. IDs are per-owner counters, so a friend's
  /// item 3 is not the same as the current user's item 3 — pass a scope
  /// when opening someone else's list or the own catalog wins.
  Product? findCatalogProduct(
    int id, {
    String? friendWishlistId,
    String? sharedBasketId,
    String? friendId,
  }) {
    if (friendWishlistId != null && friendWishlistId.isNotEmpty) {
      return friendWishlistById(friendWishlistId)
          ?.items
          .where((p) => p.id == id)
          .firstOrNull;
    }
    if (sharedBasketId != null && sharedBasketId.isNotEmpty) {
      return sharedBasketById(sharedBasketId)
          ?.items
          .where((p) => p.id == id)
          .firstOrNull;
    }
    if (friendId != null && friendId.isNotEmpty) {
      return friendSalkamalkaByFriendId(friendId)
          ?.allProducts
          .where((p) => p.id == id)
          .firstOrNull;
    }
    final own = productById(id);
    if (own != null) return own;
    for (final w in friendWishlists) {
      final hit = w.items.where((p) => p.id == id).firstOrNull;
      if (hit != null) return hit;
    }
    for (final s in sharedBaskets.values) {
      final hit = s.items.where((p) => p.id == id).firstOrNull;
      if (hit != null) return hit;
    }
    for (final s in receivedBaskets) {
      final hit = s.items.where((p) => p.id == id).firstOrNull;
      if (hit != null) return hit;
    }
    return null;
  }

  List<ProductReview> get reviewFeed {
    final byId = <String, ProductReview>{};
    for (final r in [...friendReviews, ...myReviews]) {
      byId[r.id] = r;
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  ProductReview? reviewById(String id) {
    return reviewFeed.where((r) => r.id == id).firstOrNull;
  }

  ProductReview? myReviewForProduct(int productId) {
    return myReviews.where((r) => r.productId == productId).firstOrNull;
  }

  Future<void> _restoreLocalReviews() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_reviewsKey}_${uid ?? 'guest'}');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      final restored = list
          .map(
            (e) => ProductReview.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      if (myReviews.isEmpty) {
        myReviews = restored;
      }
    } catch (_) {}
  }

  Future<void> _persistLocalReviews() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '${_reviewsKey}_${uid ?? 'guest'}',
      jsonEncode(myReviews.map((r) => r.toJson()).toList()),
    );
  }

  /// Returns null when a publish for this product is already in flight.
  Future<ProductReview?> publishReview({
    required Product product,
    required String title,
    required String body,
    int mood = 3,
    List<String> imageUrls = const [],
    List<File> newPhotos = const [],
    String? existingId,
  }) async {
    final userId = uid;
    if (userId == null) {
      throw Exception('로그인된 계정이 없어요.');
    }
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty) {
      throw Exception('제목을 입력해 주세요.');
    }
    if (trimmedBody.isEmpty) {
      throw Exception('본문을 입력해 주세요.');
    }

    return _withLock('publishReview:${existingId ?? product.id}', () async {
      final now = DateTime.now();
      final existing = existingId != null
          ? myReviews.where((r) => r.id == existingId).firstOrNull
          : myReviewForProduct(product.id);
      final reviewId = existing?.id ?? 'rv-${now.millisecondsSinceEpoch}';
      final uploaded = [...imageUrls];
      for (var i = 0; i < newPhotos.length; i++) {
        uploaded.add(
          await _storeReviewPhoto(
            userId: userId,
            reviewId: reviewId,
            file: newPhotos[i],
            index: uploaded.length,
          ),
        );
      }

      final review = existing == null
          ? ProductReview(
              id: reviewId,
              authorUid: userId,
              authorName: currentUser.name,
              authorHandle: currentUser.handle,
              authorAvatar: currentUser.avatarUrl,
              productId: product.id,
              productName: product.name,
              productImage: product.image,
              productPlatform: product.platform,
              productPrice: product.price,
              productUrl: product.productUrl,
              title: trimmedTitle,
              body: trimmedBody,
              createdAt: now,
              updatedAt: now,
              mood: mood,
              imageUrls: uploaded,
            )
          : existing.copyWith(
              title: trimmedTitle,
              body: trimmedBody,
              updatedAt: now,
              authorName: currentUser.name,
              authorHandle: currentUser.handle,
              authorAvatar: currentUser.avatarUrl,
              mood: mood,
              imageUrls: uploaded,
            );

      myReviews = [review, ...myReviews.where((r) => r.id != review.id)];
      await _persistLocalReviews();
      try {
        await _repo.upsertReview(userId, review);
      } catch (_) {
        // Local review still works if the backend is unreachable.
      }
      notifyListeners();
      return review;
    });
  }

  Future<T?> _withLock<T>(String key, Future<T> Function() action) async {
    if (!_actionLock.begin(key)) return null;
    try {
      return await action();
    } finally {
      _actionLock.end(key);
    }
  }

  Future<String> _storeReviewPhoto({
    required String userId,
    required String reviewId,
    required File file,
    required int index,
  }) async {
    try {
      return await _repo.uploadReviewPhoto(
        uid: userId,
        reviewId: reviewId,
        file: file,
        index: index,
      );
    } catch (_) {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/reviews/$reviewId');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final ext = file.path.split('.').last.toLowerCase();
      final safeExt =
          (ext == 'png' || ext == 'webp' || ext == 'jpg' || ext == 'jpeg')
          ? ext
          : 'jpg';
      final dest = File('${folder.path}/$index.$safeExt');
      await file.copy(dest.path);
      return dest.path;
    }
  }

  Future<void> deleteReview(String reviewId) async {
    final userId = uid;
    myReviews = myReviews.where((r) => r.id != reviewId).toList();
    await _persistLocalReviews();
    if (userId != null) {
      try {
        await _repo.deleteReview(userId, reviewId);
      } catch (_) {}
    }
    notifyListeners();
  }
}
