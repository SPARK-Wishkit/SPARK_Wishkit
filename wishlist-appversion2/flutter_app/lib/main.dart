import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'auth/amplify_setup.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_routes.dart';
import 'auth/cognito_auth_service.dart';
import 'data/app_store.dart';
import 'services/push_notification_service.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/friends/notifications_screen.dart';
import 'screens/mypage/follow_list_screen.dart';
import 'screens/mypage/mypage_screen.dart';
import 'screens/mypage/sent_baskets_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/reviews/my_reviews_screen.dart';
import 'screens/reviews/review_compose_screen.dart';
import 'screens/reviews/review_detail_screen.dart';
import 'screens/salkamalka/salkamalka_screen.dart';
import 'screens/share/share_intake_screen.dart';
import 'screens/shared/shared_basket_detail_screen.dart';
import 'screens/shared/shared_wishlist_screen.dart';
import 'screens/wishlist/wishlist_screen.dart';
import 'services/share_input.dart';
import 'services/webview_extract_host.dart';
import 'theme/diary_scale.dart';
import 'theme/diary_theme.dart';
import 'widgets/diary_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) AWS(Amplify) 연결: 로그인 · 데이터 · 파일
  final amplifyError = await configureAmplify();

  // 2) 앱 안 알림 배너 준비 (푸시는 5단계에서)
  await PushNotificationService.instance.init();

  // 3) 저장된 로그인 복구 → 그다음 앱 데이터 준비 (순서 중요)
  final auth = AuthController(service: CognitoAuthService());
  await auth.init();
  final store = AppStore(auth: auth, backendConfigured: amplifyError == null);
  auth.hooks = store.authHooks;
  await store.init();

  runApp(WishlistApp(auth: auth, store: store));
}

class WishlistApp extends StatefulWidget {
  const WishlistApp({super.key, required this.auth, required this.store});

  final AuthController auth;
  final AppStore store;

  @override
  State<WishlistApp> createState() => _WishlistAppState();
}

class _WishlistAppState extends State<WishlistApp> {
  static const _nativeShareChannel = MethodChannel(
    'com.softstudio.wishlist/share',
  );

  late final GoRouter router;
  StreamSubscription? _shareSub;
  String? _lastHandledShareUrl;
  DateTime? _lastHandledShareAt;

  @override
  void initState() {
    super.initState();
    router = _buildRouter(widget.auth, widget.store);
    _listenNativeShareText();
    PushNotificationService.instance.onBannerTap = () {
      router.go('/notifications');
    };
    _listenShares();
  }

  void _listenNativeShareText() {
    _nativeShareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        _handleSharedText(call.arguments as String?);
      }
    });
    _nativeShareChannel
        .invokeMethod<String>('takePendingShareText')
        .then(_handleSharedText, onError: (_) {});
  }

  void _listenShares() {
    // App already running
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedMedia,
      onError: (_) {},
    );

    // App launched by share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedMedia(files);
      // Do not replay the same cold-start share on the next app launch.
      ReceiveSharingIntent.instance.reset();
    }, onError: (_) {});
  }

  void _handleSharedMedia(List<SharedMediaFile> files) {
    final candidates = files.expand<String?>((file) {
      // Some senders attach a URL as the message of an image share, while
      // text-only senders place the complete shared text in `path`.
      return [file.message, file.path];
    });
    final input = ShareInput.fromCandidates(candidates);
    _handleSharedText(input);
  }

  void _handleSharedText(String? sharedText) {
    final input = ShareInput.fromCandidates([sharedText]);
    if (input == null) return;

    final url = ShareInput.firstUrl(input)!;
    final now = DateTime.now();
    final isImmediateDuplicate =
        url == _lastHandledShareUrl &&
        _lastHandledShareAt != null &&
        now.difference(_lastHandledShareAt!) < const Duration(seconds: 2);
    if (isImmediateDuplicate) return;

    _lastHandledShareUrl = url;
    _lastHandledShareAt = now;
    widget.store.setPendingShareUrl(input);
    router.go('/share');
  }

  @override
  void dispose() {
    _nativeShareChannel.setMethodCallHandler(null);
    PushNotificationService.instance.onBannerTap = null;
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: widget.store),
      ],
      child: MaterialApp.router(
        title: 'wishkit',
        debugShowCheckedModeBanner: false,
        theme: DiaryTheme.light,
        routerConfig: router,
        builder: (context, child) {
          final scaled =
              DiaryScale.wrap(context, child ?? const SizedBox.shrink());
          return WebViewExtractHost(child: scaled);
        },
      ),
    );
  }
}

GoRouter _buildRouter(AuthController auth, AppStore store) {
  return GoRouter(
    initialLocation: authInitialLocation(auth),
    refreshListenable: Listenable.merge([auth, store]),
    redirect: (context, state) => authRedirect(auth, state),
    routes: [
      // /login, /verify-email, /account-recovery, /welcome
      ...authRoutes,
      GoRoute(
        path: '/share',
        builder: (context, state) =>
            ShareIntakeScreen(sharedUrl: state.uri.queryParameters['url']),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) => ProductDetailScreen(
          productId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/catalog-product/:id',
        builder: (context, state) => ProductDetailScreen(
          productId: int.parse(state.pathParameters['id']!),
          friendWishlistId: state.uri.queryParameters['wishlist'],
          sharedBasketId: state.uri.queryParameters['basket'],
          friendId: state.uri.queryParameters['friend'],
        ),
      ),
      GoRoute(
        path: '/friend-wishlist/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final store = context.read<AppStore>();
          final list = store.friendWishlistById(id);
          if (list == null) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const Center(child: Text('위시리스트를 찾을 수 없어요')),
            );
          }
          return SharedWishlistScreen(
            title: list.listName,
            subtitle: '${list.friendName} 님의 공개 위시리스트',
            products: list.items,
            accentColor: DiaryColors.folderPink,
            wishlistId: list.id,
          );
        },
      ),
      GoRoute(
        path: '/followers',
        builder: (context, state) =>
            const FollowListScreen(kind: FollowListKind.followers),
      ),
      GoRoute(
        path: '/following',
        builder: (context, state) =>
            const FollowListScreen(kind: FollowListKind.following),
      ),
      GoRoute(
        path: '/reviews/write',
        builder: (context, state) {
          final productId = int.tryParse(
            state.uri.queryParameters['productId'] ?? '',
          );
          final reviewId = state.uri.queryParameters['reviewId'];
          return ReviewComposeScreen(productId: productId, reviewId: reviewId);
        },
      ),
      GoRoute(
        path: '/reviews/:id',
        builder: (context, state) =>
            ReviewDetailScreen(reviewId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/my-reviews',
        builder: (context, state) => const MyReviewsScreen(),
      ),
      GoRoute(
        path: '/sent-baskets',
        builder: (context, state) => const SentBasketsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/friend-salkamalka/:friendId',
        builder: (context, state) {
          final friendId = state.pathParameters['friendId']!;
          final store = context.read<AppStore>();
          final group = store.friendSalkamalkaByFriendId(friendId);
          if (group == null) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              body: const Center(child: Text('받은 살까말까를 찾을 수 없어요')),
            );
          }
          return SharedWishlistScreen(
            title: '${group.friendName}의 살까말까',
            subtitle: '${group.friendHandle} · 상품 ${group.itemCount}개',
            products: group.allProducts,
            accentColor: DiaryColors.folderPeach,
            emptyMessage: '보낸 상품이 없어요',
            friendId: friendId,
          );
        },
      ),
      GoRoute(
        path: '/shared/:id',
        builder: (context, state) => SharedBasketDetailScreen(
          basketId: state.pathParameters['id']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, __) => const WishlistScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/friends',
                builder: (_, __) => const FriendsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/basket',
                builder: (_, __) => const SalkamalkaScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const MyPageScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final showWishlistFab = navigationShell.currentIndex == 0;
    final showReviewFab =
        navigationShell.currentIndex == 1 && store.friendsTab == 4;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: DiaryColors.white,
          border: Border(
            top: BorderSide(color: DiaryColors.ink.withValues(alpha: 0.08)),
          ),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(
                  index: 0,
                  label: 'wishkit',
                  icon: Icons.star_border,
                  activeIcon: Icons.star,
                  shell: navigationShell,
                ),
                _NavItem(
                  index: 1,
                  label: '내 친구',
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  shell: navigationShell,
                ),
                _NavItem(
                  index: 2,
                  label: '살까말까',
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  shell: navigationShell,
                ),
                _NavItem(
                  index: 3,
                  label: '마이페이지',
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  shell: navigationShell,
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: showWishlistFab
          ? FloatingActionButton.extended(
              backgroundColor: DiaryColors.folderYellow,
              foregroundColor: DiaryColors.ink,
              onPressed: () => context.push('/share'),
              label: const Text('공유 담기'),
              icon: const Icon(Icons.add_link),
            )
          : showReviewFab
          ? FloatingActionButton.extended(
              backgroundColor: DiaryColors.folderYellow,
              foregroundColor: DiaryColors.ink,
              onPressed: () => context.push('/reviews/write'),
              label: const Text('리뷰 쓰기'),
              icon: const Icon(Icons.edit_outlined),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.shell,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final active = shell.currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => shell.goBranch(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active
                  ? DiaryColors.ink
                  : DiaryColors.ink.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OneLineText(
                label,
                textAlign: TextAlign.center,
                style: DiaryTheme.body(
                  11,
                  weight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active
                      ? DiaryColors.ink
                      : DiaryColors.ink.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
