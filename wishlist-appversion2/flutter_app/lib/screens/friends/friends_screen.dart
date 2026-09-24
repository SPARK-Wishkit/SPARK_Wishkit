import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import '../product/product_detail_screen.dart';
import '../reviews/review_widgets.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final searchCtrl = TextEditingController();
  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<AppStore>();
      if (!store.backendReady || !store.isLoggedIn) return;
      setState(() => refreshing = true);
      try {
        await store.refreshFriends();
      } finally {
        if (mounted) setState(() => refreshing = false);
      }
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(String name, String handle, String q) {
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || handle.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final q = searchCtrl.text.trim().toLowerCase();

    final followingFriends = store.friends
        .where((f) => f.isFollowing && _matchesQuery(f.name, f.username, q))
        .toList();
    // Search hits, or everyone not yet followed so 팔로우 is always available.
    final discoverFriends = store.friends
        .where((f) => !f.isFollowing && _matchesQuery(f.name, f.username, q))
        .take(40)
        .toList();
    final followers = store.followerUsers
        .where((u) => _matchesQuery(u.name, u.handle, q))
        .toList();
    final wishlistCards = store.friendWishlists.where((w) {
      final friend = store.friendById(w.friendId);
      if (friend == null || !friend.isFollowing) return false;
      return _matchesQuery(w.friendName, friend.username, q) ||
          w.listName.toLowerCase().contains(q);
    }).toList();
    final salkamalkaFeed = store.salkamalkaFeed.where((e) {
      if (q.isEmpty) return true;
      final b = e.basket;
      return _matchesQuery(b.ownerName, b.fromHandle, q) ||
          b.recipientNames.any((n) => n.toLowerCase().contains(q));
    }).toList();
    final reviews = store.reviewFeed.where((r) {
      if (q.isEmpty) return true;
      return _matchesQuery(r.authorName, r.authorHandle, q) ||
          r.title.toLowerCase().contains(q) ||
          r.productName.toLowerCase().contains(q);
    }).toList();
    final unread = store.unreadNotificationCount;
    final tab = store.friendsTab;

    return Scaffold(
      backgroundColor: DiaryColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('내 친구', style: DiaryTheme.display(34)),
                      const Spacer(),
                      if (refreshing)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: '친구 목록 새로고침',
                          onPressed: () async {
                            setState(() => refreshing = true);
                            try {
                              await store.refreshFriends();
                            } finally {
                              if (mounted) {
                                setState(() => refreshing = false);
                              }
                            }
                          },
                          icon: const Icon(Icons.refresh),
                        ),
                      IconButton(
                        tooltip: '알림',
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: const Icon(Icons.notifications_none),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '이름·아이디로 검색',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: DiaryColors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _TabChip(
                          label: '팔로잉',
                          color: DiaryColors.folderBlue,
                          active: tab == 0,
                          onTap: () => store.selectFriendsTab(0),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _TabChip(
                          label: '팔로워',
                          color: DiaryColors.folderYellow,
                          active: tab == 1,
                          onTap: () => store.selectFriendsTab(1),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _TabChip(
                          label: 'wishlist',
                          color: DiaryColors.folderPink,
                          active: tab == 2,
                          onTap: () => store.selectFriendsTab(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _TabChip(
                          label: '살까말까',
                          color: DiaryColors.folderPeach,
                          active: tab == 3,
                          onTap: () => store.selectFriendsTab(3),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _TabChip(
                          label: '리뷰',
                          color: DiaryColors.folderLilac,
                          active: tab == 4,
                          onTap: () => store.selectFriendsTab(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SpiralNotebook(
                folderColor: DiaryColors.canvas,
                border: Border.all(color: DiaryColors.fileCream, width: 3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: switch (tab) {
                    0 => _FollowingList(
                      following: followingFriends,
                      discover: discoverFriends,
                      searching: q.isNotEmpty,
                      onToggleFollow: (f) => store.toggleFollow(f.id),
                    ),
                    1 => _FollowersList(
                      followers: followers,
                      onRemove: (u) => store.removeFollower(u.uid),
                    ),
                    2 => _FriendWishlistsPane(
                      wishlists: wishlistCards,
                      followingEmpty: store.friends
                          .where((f) => f.isFollowing)
                          .isEmpty,
                    ),
                    3 => _SalkamalkaFeedPane(entries: salkamalkaFeed),
                    _ => _FriendReviewsPane(
                      reviews: reviews,
                      myUid: store.uid ?? '',
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowingList extends StatelessWidget {
  const _FollowingList({
    required this.following,
    required this.discover,
    required this.searching,
    required this.onToggleFollow,
  });

  final List<Friend> following;
  final List<Friend> discover;
  final bool searching;
  final Future<bool> Function(Friend friend) onToggleFollow;

  @override
  Widget build(BuildContext context) {
    if (following.isEmpty && discover.isEmpty) {
      return Center(
        child: Text(
          searching ? '검색 결과가 없어요' : '아직 팔로잉한 친구가 없어요',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView(
      children: [
        for (final f in following)
          PersonRow(
            name: f.name,
            handle: f.username,
            avatarUrl: f.avatar,
            subtitle: '위시리스트 ${f.wishlistCount}  ·  아이템 ${f.itemCount}',
            trailing: _FollowButton(
              isFollowing: true,
              onPressed: () => _toggle(context, f),
            ),
          ),
        if (discover.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              searching ? '검색 결과' : '친구 찾아보기',
              style: DiaryTheme.body(13, weight: FontWeight.w700),
            ),
          ),
          for (final f in discover)
            PersonRow(
              name: f.name,
              handle: f.username,
              avatarUrl: f.avatar,
              subtitle: '위시리스트 ${f.wishlistCount}  ·  아이템 ${f.itemCount}',
              trailing: _FollowButton(
                isFollowing: false,
                onPressed: () => _toggle(context, f),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _toggle(BuildContext context, Friend f) async {
    final willFollow = !f.isFollowing;
    try {
      final changed = await onToggleFollow(f);
      if (!changed || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willFollow ? '${f.name} 님을 팔로우했어요' : '${f.name} 님 팔로우를 취소했어요',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('팔로우 실패: $e')));
    }
  }
}

class _FollowersList extends StatelessWidget {
  const _FollowersList({required this.followers, required this.onRemove});

  final List<AppUser> followers;
  final Future<void> Function(AppUser user) onRemove;

  @override
  Widget build(BuildContext context) {
    if (followers.isEmpty) {
      return Center(
        child: Text(
          '아직 팔로워가 없어요',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: followers.length,
      itemBuilder: (context, i) {
        final u = followers[i];
        return PersonRow(
          name: u.name,
          handle: u.handle,
          avatarUrl: u.avatarUrl,
          trailing: OutlinedButton(
            onPressed: () => _confirmRemove(context, u),
            style: OutlinedButton.styleFrom(
              foregroundColor: DiaryColors.ink,
              side: BorderSide(color: DiaryColors.ink.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('삭제'),
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context, AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text(
          '팔로워 삭제',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        content: Text(
          '${user.name} 님을 팔로워에서 삭제할까요?\n삭제하면 이 사람은 더 이상 회원님을 팔로우하지 않아요.',
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
              style: DiaryTheme.ui(
                14,
                weight: FontWeight.w700,
                color: DiaryColors.pin,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await onRemove(user);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${user.name} 님을 팔로워에서 삭제했어요')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }
}

/// Instagram-style: following = outlined "팔로잉", not following = filled "팔로우".
class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.isFollowing, required this.onPressed});

  final bool isFollowing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (isFollowing) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: DiaryColors.ink,
          side: BorderSide(color: DiaryColors.ink.withValues(alpha: 0.35)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('팔로잉'),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: DiaryColors.ink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: const Text('팔로우'),
    );
  }
}

class _FriendWishlistsPane extends StatelessWidget {
  const _FriendWishlistsPane({
    required this.wishlists,
    required this.followingEmpty,
  });

  final List<FriendWishlist> wishlists;
  final bool followingEmpty;

  @override
  Widget build(BuildContext context) {
    if (followingEmpty) {
      return Center(
        child: Text(
          '팔로잉한 친구의 wishlist가 여기에 보여요',
          textAlign: TextAlign.center,
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    if (wishlists.isEmpty) {
      return Center(
        child: Text(
          '공개된 친구 위시리스트가 없어요',
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView(
      children: [
        for (final w in wishlists)
          WhiteProductCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.listName,
                  style: DiaryTheme.body(15, weight: FontWeight.w700),
                ),
                Text(
                  w.friendName,
                  style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: w.items
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => context.push(
                                catalogProductLocation(
                                  p.id,
                                  wishlistId: w.id,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      p.image,
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 72,
                                        height: 72,
                                        color: DiaryColors.paper,
                                        child: const Icon(Icons.image_outlined),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DiaryTheme.body(10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/friend-wishlist/${w.id}'),
                    child: const Text('위시리스트 전체보기'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SalkamalkaFeedPane extends StatelessWidget {
  const _SalkamalkaFeedPane({required this.entries});

  final List<SalkamalkaFeedEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          '아직 살까말까가 없어요',
          textAlign: TextAlign.center,
          style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
        ),
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final b = e.basket;
        return WhiteProductCard(
          backgroundColor: e.isMine ? DiaryColors.mineCard : DiaryColors.white,
          onTap: () => context.push('/shared/${b.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(
                      e.isMine
                          ? (b.fromAvatar.isNotEmpty
                                ? b.fromAvatar
                                : 'https://api.dicebear.com/7.x/thumbs/png?seed=me')
                          : (b.fromAvatar.isNotEmpty
                                ? b.fromAvatar
                                : 'https://api.dicebear.com/7.x/thumbs/png?seed=${Uri.encodeComponent(b.ownerName)}'),
                    ),
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
                                e.isMine
                                    ? '내가 보낸 살까말까'
                                    : '${b.ownerName}의 살까말까',
                                style: DiaryTheme.body(
                                  14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (e.isMine) ...[
                              const SizedBox(width: 6),
                              const MineBadge(),
                            ],
                          ],
                        ),
                        Text(
                          _salkamalkaSubtitle(e),
                          style: DiaryTheme.body(
                            11,
                            color: DiaryColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _confirmHide(context, e),
                    tooltip: '목록에서 숨기기',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: DiaryColors.inkMuted,
                    ),
                  ),
                ],
              ),
              if (b.memo.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  b.memo.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.body(13),
                ),
              ],
              if (b.items.isNotEmpty) ...[
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
              ],
            ],
          ),
        );
      },
    );
  }

  /// Hides the entry from this feed only — never deletes the basket.
  Future<void> _confirmHide(BuildContext context, SalkamalkaFeedEntry e) async {
    final store = context.read<AppStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DiaryColors.paper,
        title: Text(
          '목록에서 숨기기',
          style: DiaryTheme.ui(17, weight: FontWeight.w700),
        ),
        content: Text(
          e.isMine
              ? '이 목록에서 숨길까요? 내가 보낸 살까말까에는 남아 있어요'
              : '이 목록에서 숨길까요? 숨기면 다시 볼 수 없어요',
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
              '숨기기',
              style: DiaryTheme.ui(
                14,
                weight: FontWeight.w700,
                color: DiaryColors.pin,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.hideFromSalkamalkaFeed(e.basket.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('목록에서 숨겼어요')));
  }

  String _salkamalkaSubtitle(SalkamalkaFeedEntry e) {
    final b = e.basket;
    if (e.isMine) {
      if (b.recipientNames.isNotEmpty) {
        final names = b.recipientNames.take(2).join(', ');
        final extra = b.recipientNames.length > 2
            ? ' 외 ${b.recipientNames.length - 2}명'
            : '';
        return '$names$extra에게 보냄  ·  상품 ${b.items.length}개';
      }
      return '친구에게 보냄  ·  상품 ${b.items.length}개';
    }
    return '${b.ownerName}에게 받음  ·  상품 ${b.items.length}개';
  }
}

class _FriendReviewsPane extends StatelessWidget {
  const _FriendReviewsPane({required this.reviews, required this.myUid});

  final List<ProductReview> reviews;
  final String myUid;

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '아직 올라온 리뷰가 없어요.\n오른쪽 아래 리뷰 쓰기로 첫 글을 남겨보세요',
            textAlign: TextAlign.center,
            style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final r in reviews)
          ReviewPostCard(
            review: r,
            isMine: r.authorUid == myUid && myUid.isNotEmpty,
          ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            bottom: BorderSide(
              color: active ? DiaryColors.accent : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: DiaryTheme.body(
              13,
              weight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
