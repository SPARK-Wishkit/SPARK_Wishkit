import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      if (!store.isLoggedIn) return;
      await store.refreshNotifications();
      await store.markAllNotificationsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.visibleNotifications;

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
          '알림',
          style: DiaryTheme.ui(18, weight: FontWeight.w700),
        ),
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                '아직 알림이 없어요',
                style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final n = items[i];
                return WhiteProductCard(
                  onTap: () => _open(context, store, n),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundImage: NetworkImage(n.fromAvatar),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.message,
                              style: DiaryTheme.body(
                                14,
                                weight: n.read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _relativeTime(n.createdAt),
                              style: DiaryTheme.body(
                                11,
                                color: DiaryColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        switch (n.type) {
                          AppNotificationType.basket =>
                            Icons.shopping_bag_outlined,
                          AppNotificationType.review =>
                            Icons.menu_book_outlined,
                          AppNotificationType.list => Icons.folder_open_outlined,
                          AppNotificationType.follow =>
                            Icons.person_add_alt_1_outlined,
                          AppNotificationType.comment =>
                            Icons.chat_bubble_outline,
                        },
                        size: 18,
                        color: DiaryColors.inkMuted,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _open(BuildContext context, AppStore store, AppNotification n) {
    if (n.type == AppNotificationType.list) {
      store.selectFriendsTab(2);
      context.go('/friends');
      return;
    }
    if (n.type == AppNotificationType.review) {
      if (n.relatedId != null) {
        context.push('/reviews/${n.relatedId}');
      } else {
        context.go('/friends');
      }
      return;
    }
    if (n.type == AppNotificationType.comment) {
      if (n.relatedId != null && n.relatedId!.isNotEmpty) {
        context.push('/shared/${n.relatedId}');
        return;
      }
      if (n.fromUid.isNotEmpty) {
        context.push('/friend-salkamalka/${n.fromUid}');
      }
      return;
    }
    if (n.type == AppNotificationType.basket) {
      if (n.relatedId != null && n.relatedId!.isNotEmpty) {
        context.push('/shared/${n.relatedId}');
        return;
      }
      if (n.fromUid.isNotEmpty) {
        context.push('/friend-salkamalka/${n.fromUid}');
      }
      return;
    }
    // Follow notification — jump to followers tab via friends screen.
    context.go('/friends');
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${t.month}/${t.day}';
  }
}
