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
                        const SizedBox(height: 14),
                        if (isOwn)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DiaryButton(
                              label:
                                  store.myReviewForProduct(product.id) == null
                                  ? '이 상품 리뷰 쓰기'
                                  : '내 리뷰 보기',
                              icon: Icons.edit_outlined,
                              onPressed: () {
                                final existing = store.myReviewForProduct(
                                  product.id,
                                );
                                if (existing != null) {
                                  context.push('/reviews/${existing.id}');
                                } else {
                                  context.push(
                                    '/reviews/write?productId=${product.id}',
                                  );
                                }
                              },
                            ),
                          ),
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
