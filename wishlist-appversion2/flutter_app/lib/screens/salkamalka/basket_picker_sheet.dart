import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

/// One entry in the category step ('전체' + each custom wishlist tab).
class _PickerCategory {
  const _PickerCategory({
    required this.label,
    required this.color,
    required this.products,
  });

  final String label;
  final Color color;
  final List<Product> products;
}

/// Two-step sheet for the 살까말까 [+ 상품 추가하기] flow:
/// category list → product list with per-item checkboxes.
///
/// Pops with the products the user picked (`null` when dismissed).
class BasketPickerSheet extends StatefulWidget {
  const BasketPickerSheet({super.key, required this.store});

  final AppStore store;

  @override
  State<BasketPickerSheet> createState() => _BasketPickerSheetState();
}

class _BasketPickerSheetState extends State<BasketPickerSheet> {
  final _sheetController = DraggableScrollableController();

  /// null → category step, otherwise the opened category's product step.
  _PickerCategory? _category;
  final _selectedIds = <int>{};

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  List<_PickerCategory> get _categories {
    final store = widget.store;
    return [
      _PickerCategory(
        label: '전체',
        color: store.tabs.isEmpty
            ? DiaryColors.fileCream
            : store.tabColor(store.tabs.first),
        products: store.products,
      ),
      for (final tab in store.customTabs)
        _PickerCategory(
          label: tab.name,
          color: store.tabColor(tab),
          products: store.products.where((p) => p.listId == tab.id).toList(),
        ),
    ];
  }

  /// Product ids already sitting in the 살까말까 basket.
  Set<int> get _basketIds =>
      widget.store.basket.map((b) => b.product.id).toSet();

  /// Products of the open category that are not in the basket yet.
  List<Product> get _pickable {
    final inBasket = _basketIds;
    return (_category?.products ?? const <Product>[])
        .where((p) => !inBasket.contains(p.id))
        .toList();
  }

  void _openCategory(_PickerCategory category) {
    setState(() {
      _category = category;
      _selectedIds.clear();
    });
    if (_sheetController.isAttached && _sheetController.size < 0.85) {
      _sheetController.animateTo(
        0.85,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _backToCategories() {
    setState(() {
      _category = null;
      _selectedIds.clear();
    });
  }

  void _toggleProduct(int id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _toggleAll() {
    final pickable = _pickable;
    final allSelected =
        pickable.isNotEmpty && _selectedIds.length == pickable.length;
    setState(() {
      _selectedIds.clear();
      if (!allSelected) {
        _selectedIds.addAll(pickable.map((p) => p.id));
      }
    });
  }

  void _confirm() {
    final products = (_category?.products ?? const <Product>[])
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    Navigator.pop(context, products);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _category == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToCategories();
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (sheetCtx, scrollController) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _category == null
                ? _buildCategoryStep(scrollController)
                : _buildProductStep(scrollController),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryStep(ScrollController scrollController) {
    final categories = _categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: '카테고리에서 담기',
          onClose: () => Navigator.pop(context),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: categories.every((c) => c.products.isEmpty)
              ? Center(
                  child: Text('담을 상품이 없어요',
                      style:
                          DiaryTheme.body(14, color: DiaryColors.inkMuted)),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    final category = categories[i];
                    final count = category.products.length;
                    final disabled = count == 0;
                    return Opacity(
                      opacity: disabled ? 0.45 : 1,
                      child: WhiteProductCard(
                        indexColor: category.color,
                        onTap: disabled ? null : () => _openCategory(category),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(category.label,
                                  style: DiaryTheme.body(14,
                                      weight: FontWeight.w700)),
                            ),
                            Text('$count개',
                                style: DiaryTheme.body(13,
                                    color: DiaryColors.inkMuted)),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductStep(ScrollController scrollController) {
    final category = _category!;
    final inBasket = _basketIds;
    final pickableCount = _pickable.length;
    final selectedCount = _selectedIds.length;

    // Tristate: all picked → true, none → false, partial → indeterminate.
    final bool? allValue = pickableCount == 0 || selectedCount == 0
        ? false
        : selectedCount == pickableCount
            ? true
            : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: category.label,
          onBack: _backToCategories,
          onClose: () => Navigator.pop(context),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${category.products.length}개 중 $selectedCount개 선택',
                style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
              ),
            ),
            InkWell(
              onTap: pickableCount == 0 ? null : _toggleAll,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('전체 선택',
                        style: DiaryTheme.body(12,
                            color: pickableCount == 0
                                ? DiaryColors.inkSoft
                                : DiaryColors.inkMuted)),
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: Checkbox(
                        tristate: true,
                        value: allValue,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged:
                            pickableCount == 0 ? null : (_) => _toggleAll(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: category.products.isEmpty
              ? Center(
                  child: Text('이 카테고리에 상품이 없어요',
                      style:
                          DiaryTheme.body(14, color: DiaryColors.inkMuted)),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: category.products.length,
                  itemBuilder: (context, i) {
                    final product = category.products[i];
                    final already = inBasket.contains(product.id);
                    return _ProductRow(
                      product: product,
                      alreadyInBasket: already,
                      checked: already || _selectedIds.contains(product.id),
                      onToggle:
                          already ? null : () => _toggleProduct(product.id),
                    );
                  },
                ),
        ),
        const SizedBox(height: 4),
        DiaryButton(
          label: '$selectedCount개 담기',
          filled: true,
          color: DiaryColors.folderPeach,
          icon: Icons.add_shopping_cart,
          onPressed: selectedCount == 0 ? null : _confirm,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose, this.onBack});

  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            tooltip: '뒤로',
            icon: const Icon(Icons.arrow_back),
          ),
        Expanded(
          child: Text(title,
              style: DiaryTheme.body(16, weight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.alreadyInBasket,
    required this.checked,
    required this.onToggle,
  });

  final Product product;
  final bool alreadyInBasket;
  final bool checked;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: alreadyInBasket ? 0.6 : 1,
      child: WhiteProductCard(
        onTap: onToggle,
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onToggle == null ? null : (_) => onToggle!(),
              ),
            ),
            const SizedBox(width: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                product.image,
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 58,
                  height: 58,
                  color: DiaryColors.paper,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.platform,
                      style:
                          DiaryTheme.body(11, color: DiaryColors.inkMuted)),
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DiaryTheme.body(14, weight: FontWeight.w700)),
                  Text(formatWon(product.price),
                      style: DiaryTheme.body(13, weight: FontWeight.w600)),
                ],
              ),
            ),
            if (alreadyInBasket) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DiaryColors.ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('담김',
                    style: DiaryTheme.body(10,
                        weight: FontWeight.w700,
                        color: DiaryColors.inkMuted)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
