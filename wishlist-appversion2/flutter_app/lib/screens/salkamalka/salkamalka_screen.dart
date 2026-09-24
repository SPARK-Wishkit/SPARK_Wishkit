import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'basket_picker_sheet.dart';
import 'share_to_friends_sheet.dart';

class SalkamalkaScreen extends StatelessWidget {
  const SalkamalkaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final selected = store.basket.where((b) => b.isSelected).length;

    return Scaffold(
      backgroundColor: DiaryColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: kMinInteractiveDimension,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('살까말까', style: DiaryTheme.display(34)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: DiaryGridPaper(
                  border: Border.all(color: DiaryColors.fileCream, width: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '📌 선택된 아이템 총 $selected개',
                        style: DiaryTheme.body(13, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: store.basket.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: OneLineText(
                                    '고민중인 상품을 담아 친구와 공유해보세요',
                                    textAlign: TextAlign.center,
                                    style: DiaryTheme.body(
                                      14,
                                      color: DiaryColors.inkMuted,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: store.basket.length,
                                itemBuilder: (context, i) {
                                  final item = store.basket[i];
                                  final pinColors = [
                                    DiaryColors.pin,
                                    DiaryColors.folderYellow,
                                    DiaryColors.accent,
                                  ];
                                  return Stack(
                                    children: [
                                      WhiteProductCard(
                                        child: Row(
                                          children: [
                                            Checkbox(
                                              value: item.isSelected,
                                              onChanged: (_) =>
                                                  store.toggleBasketSelected(
                                                    item.product.id,
                                                  ),
                                            ),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.network(
                                                item.product.image,
                                                width: 58,
                                                height: 58,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.product.platform,
                                                    style: DiaryTheme.body(
                                                      11,
                                                      color:
                                                          DiaryColors.inkMuted,
                                                    ),
                                                  ),
                                                  Text(
                                                    item.product.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: DiaryTheme.body(
                                                      14,
                                                      weight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  Text(
                                                    formatWon(
                                                      item.product.price,
                                                    ),
                                                    style: DiaryTheme.body(
                                                      13,
                                                      weight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  store.removeFromBasket(
                                                    item.product.id,
                                                  ),
                                              icon: const Icon(
                                                Icons.close,
                                                size: 18,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: 8,
                                        top: 2,
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 18,
                                          color:
                                              pinColors[i % pinColors.length],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: DiaryButton(
                              label: '상품 추가하기',
                              icon: Icons.add,
                              onPressed: () =>
                                  _openPickFromWishlistSheet(context, store),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ShareBasketButton(
                              store: store,
                              selected: selected,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPickFromWishlistSheet(
    BuildContext context,
    AppStore store,
  ) async {
    final picked = await showModalBottomSheet<List<Product>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => BasketPickerSheet(store: store),
    );
    if (picked == null || picked.isEmpty) return;
    await store.addManyToBasket(picked);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${picked.length}개를 담았어요')));
  }
}

class _ShareBasketButton extends StatefulWidget {
  const _ShareBasketButton({required this.store, required this.selected});

  final AppStore store;
  final int selected;

  @override
  State<_ShareBasketButton> createState() => _ShareBasketButtonState();
}

class _ShareBasketButtonState extends State<_ShareBasketButton> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return DiaryButton(
      label: _sharing
          ? '보내는 중...'
          : widget.selected == 0
          ? '공유하기'
          : '공유하기 (${widget.selected})',
      filled: true,
      color: DiaryColors.folderPeach,
      icon: Icons.ios_share,
      onPressed: widget.selected == 0 || _sharing ? null : _share,
    );
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final picked = await showShareToFriendsSheet(
        context: context,
        store: widget.store,
      );
      if (picked == null || picked.friendIds.isEmpty) return;
      final sent = await widget.store.sendBasketToFriends(
        picked.friendIds.toList(),
        memo: picked.memo,
      );
      if (!sent || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${picked.friendIds.length}명의 친구에게 살까말까를 보냈어요')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
