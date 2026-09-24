import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../theme/avatar_presets.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

class ReviewPostCard extends StatelessWidget {
  const ReviewPostCard({
    super.key,
    required this.review,
    this.showAuthor = true,
    this.isMine = false,
  });

  final ProductReview review;
  final bool showAuthor;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final mood = ReviewMood.byLevel(review.mood);
    final hero = review.imageUrls.isNotEmpty
        ? review.imageUrls.first
        : review.productImage;

    return WhiteProductCard(
      onTap: () => context.push('/reviews/${review.id}'),
      backgroundColor: isMine ? DiaryColors.mineCard : DiaryColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAuthor) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(review.authorAvatar),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              review.authorName,
                              style: DiaryTheme.body(13, weight: FontWeight.w700),
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 6),
                            const MineBadge(),
                          ],
                        ],
                      ),
                      Text(
                        '${review.authorHandle}  ·  ${relativeTime(review.createdAt)}',
                        style: DiaryTheme.body(
                          11,
                          color: DiaryColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                MoodFace(mood: mood, size: 36),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (hero.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: ReviewPhoto(src: hero, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            review.productPlatform,
            style: DiaryTheme.product(11, color: DiaryColors.inkMuted),
          ),
          Text(
            review.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DiaryTheme.product(12, color: DiaryColors.inkSoft),
          ),
          const SizedBox(height: 6),
          Text(
            review.title,
            style: DiaryTheme.body(16, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            review.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DiaryTheme.product(13, color: DiaryColors.ink),
          ),
          if (!showAuthor) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                MoodFace(mood: mood, size: 28),
                const SizedBox(width: 6),
                Text(
                  '${mood.label}  ·  ${relativeTime(review.createdAt)}',
                  style: DiaryTheme.body(11, color: DiaryColors.inkMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MoodFace extends StatelessWidget {
  const MoodFace({super.key, required this.mood, this.size = 40});

  final ReviewMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.network(
        mood.url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => SizedBox(
          width: size,
          height: size,
          child: Icon(Icons.sentiment_satisfied_alt, size: size * 0.7),
        ),
      ),
    );
  }
}

class ReviewPhoto extends StatelessWidget {
  const ReviewPhoto({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
  });

  final String src;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final isFile = src.startsWith('/') || src.startsWith('file:');
    if (isFile) {
      final path = src.startsWith('file:') ? Uri.parse(src).toFilePath() : src;
      return Image.file(
        File(path),
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          color: DiaryColors.paper,
          child: const Icon(Icons.image_outlined),
        ),
      );
    }
    return Image.network(
      src,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: DiaryColors.paper,
        child: const Icon(Icons.image_outlined),
      ),
    );
  }
}

String relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${t.year}.${t.month}.${t.day}';
}
