import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../theme/avatar_presets.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'review_widgets.dart';

class ReviewDetailScreen extends StatelessWidget {
  const ReviewDetailScreen({super.key, required this.reviewId});

  final String reviewId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final review = store.reviewById(reviewId);
    if (review == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('리뷰를 찾을 수 없어요')),
      );
    }
    final isMine = review.authorUid == store.uid;

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
          '리뷰',
          style: DiaryTheme.ui(18, weight: FontWeight.w700),
        ),
        actions: [
          if (isMine)
            IconButton(
              tooltip: '수정',
              onPressed: () => context.push(
                '/reviews/write?productId=${review.productId}&reviewId=${review.id}',
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (isMine)
            IconButton(
              tooltip: '삭제',
              onPressed: () => _confirmDelete(context, store, review.id),
              icon: Icon(Icons.delete_outline, color: DiaryColors.pin),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(review.authorAvatar),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.authorName,
                      style: DiaryTheme.body(15, weight: FontWeight.w700),
                    ),
                    Text(
                      '${review.authorHandle}  ·  ${relativeTime(review.createdAt)}',
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                  ],
                ),
              ),
              MoodFace(mood: ReviewMood.byLevel(review.mood), size: 44),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ReviewMood.byLevel(review.mood).label,
            textAlign: TextAlign.right,
            style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
          ),
          const SizedBox(height: 16),
          WhiteProductCard(
            margin: EdgeInsets.zero,
            onTap: () => context.push('/catalog-product/${review.productId}'),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    review.productImage,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: DiaryColors.paper,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.productPlatform,
                        style: DiaryTheme.product(
                          11,
                          color: DiaryColors.inkMuted,
                        ),
                      ),
                      Text(
                        review.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DiaryTheme.product(
                          14,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        formatWon(review.productPrice),
                        style: DiaryTheme.product(12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (review.imageUrls.isNotEmpty) ...[
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: review.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ReviewPhoto(src: review.imageUrls[i]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            review.title,
            style: DiaryTheme.display(28),
          ),
          const SizedBox(height: 12),
          Text(
            review.body,
            style: DiaryTheme.product(16, color: DiaryColors.ink),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppStore store,
    String id,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text('리뷰 삭제', style: DiaryTheme.ui(17, weight: FontWeight.w700)),
        content: Text(
          '이 리뷰를 삭제할까요? 친구 피드에서도 사라져요.',
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '삭제',
              style: DiaryTheme.ui(14, weight: FontWeight.w700, color: DiaryColors.pin),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await store.deleteReview(id);
    if (!context.mounted) return;
    context.pop();
  }
}
