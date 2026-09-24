import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../theme/diary_theme.dart';

const kShareMemoMaxLength = 500;

/// Friend picker plus the memo that goes out with a 살까말까 share.
Future<({Set<String> friendIds, String memo})?> showShareToFriendsSheet({
  required BuildContext context,
  required AppStore store,
  String title = '보낼 친구 선택',
  String confirmLabel = '보내기',
  String initialMemo = '',
}) async {
  final following = store.friends.where((f) => f.isFollowing).toList();
  if (following.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('팔로잉한 친구가 없어요. 먼저 친구를 추가해 주세요.')),
    );
    return null;
  }

  final selected = <String>{};
  final memoCtrl = TextEditingController(text: initialMemo);
  var confirming = false;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DiaryColors.paper,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: DiaryTheme.body(16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '고민되는 이유를 짧게 적어 같이 보내요',
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: memoCtrl,
                      maxLines: 3,
                      maxLength: kShareMemoMaxLength,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        hintText: '예: 이걸 사 말아',
                        filled: true,
                        fillColor: DiaryColors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: following.length,
                        itemBuilder: (context, i) {
                          final f = following[i];
                          final checked = selected.contains(f.id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selected.add(f.id);
                                } else {
                                  selected.remove(f.id);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              backgroundImage: NetworkImage(f.avatar),
                            ),
                            title: Text(f.name),
                            subtitle: Text(f.username),
                          );
                        },
                      ),
                    ),
                    FilledButton(
                      onPressed: selected.isEmpty || confirming
                          ? null
                          : () {
                              setModalState(() => confirming = true);
                              Navigator.pop(sheetCtx, true);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: DiaryColors.ink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('$confirmLabel (${selected.length})'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
  final memo = memoCtrl.text.trim();
  memoCtrl.dispose();
  if (confirmed != true || selected.isEmpty) return null;
  return (friendIds: selected, memo: memo);
}
