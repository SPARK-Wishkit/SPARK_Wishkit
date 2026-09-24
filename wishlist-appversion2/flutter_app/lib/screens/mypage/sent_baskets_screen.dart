import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import '../salkamalka/share_to_friends_sheet.dart';

class SentBasketsScreen extends StatelessWidget {
  const SentBasketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final baskets = store.sentBaskets;

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
          '내가 보낸 살까말까',
          style: DiaryTheme.ui(18, weight: FontWeight.w700),
        ),
      ),
      body: baskets.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '아직 보낸 살까말까가 없어요.\n살까말까 탭에서 친구에게 보내면 여기에 쌓여요.',
                  textAlign: TextAlign.center,
                  style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: baskets.length,
              itemBuilder: (context, i) {
                final b = baskets[i];
                return WhiteProductCard(
                  onTap: () => context.push('/shared/${b.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        style: DiaryTheme.body(15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(b),
                        style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                      ),
                      if (b.memo.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          b.memo.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DiaryTheme.body(13),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 56,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final p in b.items.take(8))
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    p.image,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 56,
                                      height: 56,
                                      color: DiaryColors.paper,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () =>
                              showSentBasketShareSheet(context, store, b),
                          child: const Text('다시 보내기'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _subtitle(SharedBasket b) {
    final when = '${b.createdAt.month}/${b.createdAt.day}';
    if (b.recipientNames.isNotEmpty) {
      final names = b.recipientNames.take(2).join(', ');
      final extra = b.recipientNames.length > 2
          ? ' 외 ${b.recipientNames.length - 2}명'
          : '';
      return '$when  ·  $names$extra  ·  상품 ${b.items.length}개';
    }
    return '$when  ·  상품 ${b.items.length}개';
  }
}

Future<void> showSentBasketShareSheet(
  BuildContext context,
  AppStore store,
  SharedBasket basket,
) async {
  final picked = await showShareToFriendsSheet(
    context: context,
    store: store,
    title: '다시 보낼 친구',
    confirmLabel: '다시 보내기',
    initialMemo: basket.memo,
  );
  if (picked == null || picked.friendIds.isEmpty || !context.mounted) return;
  try {
    final sent = await store.resendBasketToFriends(
      items: basket.items,
      friendIds: picked.friendIds.toList(),
      existingId: basket.id,
      memo: picked.memo,
    );
    if (!sent || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${picked.friendIds.length}명의 친구에게 다시 보냈어요')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}
