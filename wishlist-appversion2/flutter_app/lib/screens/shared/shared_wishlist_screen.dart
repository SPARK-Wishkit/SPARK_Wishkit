import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import '../product/product_detail_screen.dart';
import '../wishlist/wishlist_screen.dart';

/// Read-only wishlist list UI (friend lists + shared basket URL views).
/// Matches the own-wishlist card layout (product row → detail).
class SharedWishlistScreen extends StatelessWidget {
  const SharedWishlistScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.products,
    this.accentColor,
    this.emptyMessage = '아직 공개된 아이템이 없어요',
    this.onShare,
    this.wishlistId,
    this.basketId,
    this.friendId,
  });

  final String title;
  final String subtitle;
  final List<Product> products;
  final Color? accentColor;
  final String emptyMessage;
  final VoidCallback? onShare;
  final String? wishlistId;
  final String? basketId;
  final String? friendId;

  @override
  Widget build(BuildContext context) {
    final border = accentColor ?? DiaryColors.fileSand;

    return Scaffold(
      backgroundColor: DiaryColors.canvas,
      appBar: AppBar(
        backgroundColor: DiaryColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          title,
          style: DiaryTheme.ui(16, weight: FontWeight.w700),
        ),
        actions: [
          if (onShare != null)
            IconButton(
              tooltip: '다시 보내기',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  subtitle,
                  style: DiaryTheme.ui(13, color: DiaryColors.inkMuted),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    border: Border.all(color: border, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: DiaryGridPaper(
                      padding: EdgeInsets.zero,
                      borderRadius: 0,
                      child: products.isEmpty
                          ? Center(
                              child: Text(
                                emptyMessage,
                                style: DiaryTheme.ui(
                                  14,
                                  color: DiaryColors.inkMuted,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                              itemCount: products.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = products[i];
                                return WishlistProductCard(
                                  product: p,
                                  onOpen: () => context.push(
                                    catalogProductLocation(
                                      p.id,
                                      wishlistId: wishlistId,
                                      basketId: basketId,
                                      friendId: friendId,
                                    ),
                                  ),
                                );
                              },
                            ),
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
