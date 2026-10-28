import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

enum FollowListKind { followers, following }

/// Shows the current user's followers or following list, loaded from
/// the AWS Follow table (AccountRepository.followerIds / followingIds).
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({super.key, required this.kind});

  final FollowListKind kind;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<AppUser>? _users;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = context.read<AppStore>();
      final users = widget.kind == FollowListKind.followers
          ? await store.loadFollowers()
          : await store.loadFollowingUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFollowers = widget.kind == FollowListKind.followers;
    final title = isFollowers ? '팔로워' : '팔로잉';
    final emptyText = isFollowers ? '팔로워가 없습니다' : '팔로우하고 있는 사람이 없습니다';

    return Scaffold(
      backgroundColor: DiaryColors.canvas,
      appBar: AppBar(
        backgroundColor: DiaryColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(title, style: DiaryTheme.ui(16, weight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: DiaryTheme.body(14, color: DiaryColors.pin),
                    ),
                  )
                : (_users == null || _users!.isEmpty)
                    ? Center(
                        child: Text(
                          emptyText,
                          style:
                              DiaryTheme.body(14, color: DiaryColors.inkMuted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _users!.length,
                        itemBuilder: (context, i) {
                          final u = _users![i];
                          return PersonRow(
                            name: u.name,
                            handle: u.handle,
                            avatarUrl: u.avatarUrl,
                            trailing: isFollowers
                                ? OutlinedButton(
                                    onPressed: () => _confirmRemove(u),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: DiaryColors.ink,
                                      side: BorderSide(
                                        color: DiaryColors.ink
                                            .withValues(alpha: 0.35),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                    child: const Text('삭제'),
                                  )
                                : null,
                          );
                        },
                      ),
      ),
    );
  }

  Future<void> _confirmRemove(AppUser user) async {
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
    if (ok != true || !mounted) return;
    try {
      await context.read<AppStore>().removeFollower(user.uid);
      setState(() {
        _users = _users?.where((u) => u.uid != user.uid).toList();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${user.name} 님을 팔로워에서 삭제했어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }
}
