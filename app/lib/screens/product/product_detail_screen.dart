import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

/// Detail route for a product that may belong to someone else.
/// IDs collide across owners, so friend/basket/friend scopes must travel
/// with the id.
String catalogProductLocation(
  int productId, {
  String? wishlistId,
  String? basketId,
  String? friendId,
}) {
  final query = <String, String>{
    if (wishlistId != null && wishlistId.isNotEmpty) 'wishlist': wishlistId,
    if (basketId != null && basketId.isNotEmpty) 'basket': basketId,
    if (friendId != null && friendId.isNotEmpty) 'friend': friendId,
  };
  return Uri(
    path: '/catalog-product/$productId',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.friendWishlistId,
    this.sharedBasketId,
    this.friendId,
  });

  final int productId;
  final String? friendWishlistId;
  final String? sharedBasketId;
  final String? friendId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late final TextEditingController memoCtrl;

  Product? _lookup(AppStore store) {
    return store.findCatalogProduct(
      widget.productId,
      friendWishlistId: widget.friendWishlistId,
      sharedBasketId: widget.sharedBasketId,
      friendId: widget.friendId,
    );
  }

  bool get _openedFromSomeoneElse =>
      (widget.friendWishlistId != null &&
          widget.friendWishlistId!.isNotEmpty) ||
      (widget.sharedBasketId != null && widget.sharedBasketId!.isNotEmpty) ||
      (widget.friendId != null && widget.friendId!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    final product = _lookup(context.read<AppStore>());
    memoCtrl = TextEditingController(text: product?.memo ?? '');
  }

  @override
  void dispose() {
    memoCtrl.dispose();
    super.dispose();
  }

  bool _refreshing = false;

  Future<void> _refreshPrice(int productId) async {
    if (_refreshing) return;
    final store = context.read<AppStore>();
    setState(() => _refreshing = true);
    PriceRefreshResult result;
    try {
      result = await store.refreshProductPrice(productId);
      if (result.status == PriceRefreshStatus.needsConfirm &&
          result.info != null &&
          mounted) {
        final ok = await _confirmUncertainPrice(result);
        if (!ok) return; // 사용자가 "그대로 두기" — 따로 안내하지 않는다.
        result = await store.applyRefreshedPrice(productId, result.info!);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (!mounted) return;
    final message = switch (result.status) {
      PriceRefreshStatus.updated =>
        '가격이 바뀌었어요: ${formatWon(result.previousPrice ?? 0)} → '
            '${formatWon(result.newPrice ?? 0)}',
      PriceRefreshStatus.unchanged => '가격 변동이 없어요',
      PriceRefreshStatus.tooSoon => '방금 확인했어요. 잠시 후 다시 시도해 주세요',
      PriceRefreshStatus.busy => '가격을 확인하는 중이에요',
      PriceRefreshStatus.failed => '가격을 읽지 못했어요. 기존 가격을 그대로 둘게요',
      PriceRefreshStatus.unavailable => '상품 링크가 없어 새로고침할 수 없어요',
      PriceRefreshStatus.needsConfirm => '가격을 확인하지 못했어요',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmUncertainPrice(PriceRefreshResult result) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이 가격이 맞나요?'),
        content: Text(
          '새로 읽은 가격: ${formatWon(result.newPrice ?? 0)}\n'
          '지금 저장된 가격: ${formatWon(result.previousPrice ?? 0)}\n\n'
          '쇼핑몰 화면에서 가격을 확실히 찾지 못했어요. '
          '쿠폰·회원가가 아닌지 확인 후 바꿔 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('그대로 두기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('바꾸기'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final product = _lookup(store);
    if (product == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('상품을 찾을 수 없어요')),
      );
    }
    final isOwn =
        !_openedFromSomeoneElse && store.productById(product.id) != null;
    final tab = store.tabs.firstWhere(
      (t) => t.id == product.listId,
      orElse: () => store.tabs.first,
    );
    final folderColor = store.tabColor(tab);

    return Scaffold(
      backgroundColor: folderColor,
      appBar: AppBar(
        backgroundColor: DiaryColors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.go('/'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: ClipPath(
                  clipper: _TornTopClipper(),
                  child: DiaryGridPaper(
                    borderRadius: 0,
                    padding: const EdgeInsets.fromLTRB(14, 28, 14, 14),
                    child: ListView(
                      children: [
                        WhiteProductCard(
                          margin: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Image.network(
                                    product.image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        Container(color: DiaryColors.grid),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                product.platform,
                                style: DiaryTheme.product(
                                  12,
                                  color: DiaryColors.inkMuted,
                                ),
                              ),
                              Text(
                                product.name,
                                style: DiaryTheme.product(
                                  18,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    formatWon(product.price),
                                    style: DiaryTheme.product(
                                      20,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  if (product.originalPrice != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      formatWon(product.originalPrice!),
                                      style:
                                          DiaryTheme.product(
                                            13,
                                            color: DiaryColors.inkSoft,
                                          ).copyWith(
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                              if (product.discount != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: DiaryColors.folderPeach,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '↘ ${product.discount}% 할인 중',
                                    style: DiaryTheme.body(
                                      12,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              if (isOwn &&
                                  (product.productUrl?.trim().isNotEmpty ??
                                      false)) ...[
                                const SizedBox(height: 10),
                                _PriceRefreshRow(
                                  checkedAt: store.priceCheckedAt(product.id),
                                  refreshing: _refreshing,
                                  onRefresh: () => _refreshPrice(product.id),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: DiaryColors.ink.withValues(alpha: 0.7),
                              width: 1.4,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '고민하는 이유',
                                style: DiaryTheme.body(
                                  14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              if (isOwn)
                                TextField(
                                  controller: memoCtrl,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    hintText: '이 상품을 고민하는 이유를 남겨보세요',
                                    hintStyle: DiaryTheme.body(
                                      13,
                                      color: DiaryColors.inkSoft,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  onChanged: (v) =>
                                      store.updateMemo(product.id, v),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    product.memo?.trim().isNotEmpty == true
                                        ? product.memo!
                                        : '공유된 상품 · 메모는 소유자만 작성할 수 있어요',
                                    style: DiaryTheme.body(
                                      13,
                                      color: DiaryColors.inkSoft,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isOwn && (product.tagImageUrl ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _TagPhotoRow(url: product.tagImageUrl!),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: DiaryButton(
                                label: '바구니에 추가',
                                icon: Icons.shopping_basket_outlined,
                                onPressed: () async {
                                  await store.addToBasket(product);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('살까말까 바구니에 담았어요'),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DiaryButton(
                                label: '상품 보러가기',
                                filled: true,
                                color: DiaryColors.folderMint,
                                icon: Icons.open_in_new,
                                onPressed: () async {
                                  final url =
                                      product.productUrl ??
                                      'https://www.musinsa.com';
                                  await launchUrl(
                                    Uri.parse(url),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 태그 사진으로 담은 상품의 태그 사진: 작은 미리보기 + "태그 사진 보기" (누르면 크게).
/// 본인 상품에만 보인다(친구 공개 목록에는 주소 자체가 없다).
class _TagPhotoRow extends StatelessWidget {
  const _TagPhotoRow({required this.url});

  final String url;

  void _openFull(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            // 두 손가락으로 확대해서 작은 글씨(품번)도 볼 수 있게.
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '태그 사진을 불러오지 못했어요',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openFull(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: DiaryColors.ink.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: DiaryColors.grid,
                  child: const Icon(Icons.broken_image_outlined, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '태그 사진',
                    style: DiaryTheme.body(14, weight: FontWeight.w700),
                  ),
                  Text(
                    '담을 때 찍은 태그예요 · 눌러서 크게 보기',
                    style: DiaryTheme.body(12, color: DiaryColors.inkSoft),
                  ),
                ],
              ),
            ),
            const Icon(Icons.zoom_in, size: 20),
          ],
        ),
      ),
    );
  }
}

/// "가격 확인: 3시간 전   [↻ 가격 새로고침]" 한 줄.
class _PriceRefreshRow extends StatelessWidget {
  const _PriceRefreshRow({
    required this.checkedAt,
    required this.refreshing,
    required this.onRefresh,
  });

  final DateTime? checkedAt;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            checkedAt == null
                ? '담을 때 가격이에요'
                : '가격 확인: ${relativeCheckedLabel(checkedAt!, DateTime.now())}',
            style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
          ),
        ),
        TextButton.icon(
          onPressed: refreshing ? null : onRefresh,
          style: TextButton.styleFrom(
            foregroundColor: DiaryColors.ink,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          icon: refreshing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(
            refreshing ? '확인 중…' : '가격 새로고침',
            style: DiaryTheme.body(12, weight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// "방금", "5분 전", "3시간 전", "2일 전".
String relativeCheckedLabel(DateTime at, DateTime now) {
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  if (diff.inDays < 1) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}

class _TornTopClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, 18);
    const step = 18.0;
    for (double x = 0; x <= size.width; x += step) {
      path.quadraticBezierTo(x + step / 2, 0, x + step, 18);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
