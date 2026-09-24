import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'review_widgets.dart';

class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final reviews = store.myReviews;

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
          '내 리뷰',
          style: DiaryTheme.ui(18, weight: FontWeight.w700),
        ),
      ),
      body: reviews.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '아직 쓴 리뷰가 없어요',
                      style: DiaryTheme.body(15, color: DiaryColors.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    DiaryButton(
                      label: '첫 리뷰 쓰기',
                      icon: Icons.edit_outlined,
                      filled: true,
                      color: DiaryColors.folderYellow,
                      onPressed: () => context.push('/reviews/write'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                for (final r in reviews)
                  ReviewPostCard(review: r, showAuthor: false),
              ],
            ),
    );
  }
}
