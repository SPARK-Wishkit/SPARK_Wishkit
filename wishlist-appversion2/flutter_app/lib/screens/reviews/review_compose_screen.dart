import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/avatar_presets.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'review_widgets.dart';

class ReviewComposeScreen extends StatefulWidget {
  const ReviewComposeScreen({super.key, this.productId, this.reviewId});

  final int? productId;
  final String? reviewId;

  @override
  State<ReviewComposeScreen> createState() => _ReviewComposeScreenState();
}

class _ReviewComposeScreenState extends State<ReviewComposeScreen> {
  static const _maxPhotos = 6;

  Product? selected;
  late final TextEditingController titleCtrl;
  late final TextEditingController bodyCtrl;
  int mood = 3;
  List<String> existingPhotos = [];
  final List<File> newPhotos = [];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    ProductReview? existing;
    if (widget.reviewId != null) {
      existing = store.reviewById(widget.reviewId!);
    }
    existing ??= widget.productId != null
        ? store.myReviewForProduct(widget.productId!)
        : null;

    if (existing != null) {
      selected =
          store.findCatalogProduct(existing.productId) ??
          Product(
            id: existing.productId,
            listId: '',
            name: existing.productName,
            price: existing.productPrice,
            image: existing.productImage,
            platform: existing.productPlatform,
            productUrl: existing.productUrl,
          );
      titleCtrl = TextEditingController(text: existing.title);
      bodyCtrl = TextEditingController(text: existing.body);
      mood = existing.mood;
      existingPhotos = [...existing.imageUrls];
    } else {
      selected = widget.productId != null
          ? store.findCatalogProduct(widget.productId!)
          : null;
      titleCtrl = TextEditingController();
      bodyCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    bodyCtrl.dispose();
    super.dispose();
  }

  int get _photoCount => existingPhotos.length + newPhotos.length;

  Future<void> _pickPhotos() async {
    if (_photoCount >= _maxPhotos) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사진은 최대 $_maxPhotos장까지 넣을 수 있어요')));
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: DiaryColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text('갤러리에서 선택', style: DiaryTheme.body(14)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text('카메라로 촬영', style: DiaryTheme.body(14)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final remaining = _maxPhotos - _photoCount;
      final picked = await picker.pickMultiImage(
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked.isEmpty) return;
      setState(() {
        newPhotos.addAll(picked.take(remaining).map((x) => File(x.path)));
      });
    } else {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (shot == null) return;
      setState(() => newPhotos.add(File(shot.path)));
    }
  }

  Future<void> _publish() async {
    if (saving) return;
    final product = selected;
    if (product == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('리뷰할 상품을 골라 주세요')));
      return;
    }
    setState(() => saving = true);
    try {
      final store = context.read<AppStore>();
      final existing = store.myReviewForProduct(product.id);
      final review = await store.publishReview(
        product: product,
        title: titleCtrl.text,
        body: bodyCtrl.text,
        mood: mood,
        imageUrls: existingPhotos,
        newPhotos: newPhotos,
        existingId: existing?.id,
      );
      if (!mounted || review == null) return;
      context.pushReplacement('/reviews/${review.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final editing =
        selected != null && store.myReviewForProduct(selected!.id) != null;

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
          editing ? '리뷰 수정' : '리뷰 쓰기',
          style: DiaryTheme.ui(18, weight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : _publish,
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    editing ? '수정' : '올리기',
                    style: DiaryTheme.ui(
                      15,
                      weight: FontWeight.w700,
                      color: DiaryColors.accent,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (selected == null)
            _ProductPicker(
              products: store.products,
              onPick: (p) => setState(() => selected = p),
            )
          else ...[
            WhiteProductCard(
              margin: EdgeInsets.zero,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      selected!.image,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: DiaryColors.paper,
                        child: const Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected!.platform,
                          style: DiaryTheme.product(
                            11,
                            color: DiaryColors.inkMuted,
                          ),
                        ),
                        Text(
                          selected!.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DiaryTheme.product(
                            14,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.productId == null && widget.reviewId == null)
                    TextButton(
                      onPressed: () => setState(() => selected = null),
                      child: const Text('바꾸기'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '이 상품, 어땠어요?',
              style: DiaryTheme.body(15, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final m in ReviewMood.all) ...[
                  if (m.level > 1) const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => mood = m.level),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: mood == m.level ? 1 : 0.45,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: mood == m.level
                                      ? DiaryColors.accent
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: MoodFace(mood: m, size: 44),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DiaryTheme.body(
                                10,
                                weight: mood == m.level
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: mood == m.level
                                    ? DiaryColors.ink
                                    : DiaryColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Text('사진 첨부', style: DiaryTheme.body(15, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < existingPhotos.length; i++)
                    _PhotoThumb(
                      child: ReviewPhoto(src: existingPhotos[i]),
                      onRemove: () =>
                          setState(() => existingPhotos.removeAt(i)),
                    ),
                  for (var i = 0; i < newPhotos.length; i++)
                    _PhotoThumb(
                      child: Image.file(newPhotos[i], fit: BoxFit.cover),
                      onRemove: () => setState(() => newPhotos.removeAt(i)),
                    ),
                  if (_photoCount < _maxPhotos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: _pickPhotos,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: DiaryColors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: DiaryColors.ink.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_photo_alternate_outlined),
                              const SizedBox(height: 4),
                              Text('추가', style: DiaryTheme.body(11)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              style: DiaryTheme.body(22, weight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '제목을 적어보세요',
                hintStyle: DiaryTheme.body(22, color: DiaryColors.inkSoft),
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1),
            TextField(
              controller: bodyCtrl,
              minLines: 8,
              maxLines: null,
              style: DiaryTheme.product(15),
              decoration: InputDecoration(
                hintText: '이 상품에 대한 솔직한 이야기를 블로그처럼 남겨보세요.',
                hintStyle: DiaryTheme.product(15, color: DiaryColors.inkSoft),
                border: InputBorder.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 88, height: 88, child: child),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({required this.products, required this.onPick});

  final List<Product> products;
  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(
          children: [
            Text(
              '위시리스트에 담긴 상품이 없어요',
              style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              '상품을 담은 뒤 리뷰를 쓸 수 있어요',
              style: DiaryTheme.body(12, color: DiaryColors.inkSoft),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '리뷰할 상품을 고르세요',
          style: DiaryTheme.body(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final p in products)
          WhiteProductCard(
            onTap: () => onPick(p),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    p.image,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 52,
                      height: 52,
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
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DiaryTheme.product(13, weight: FontWeight.w700),
                      ),
                      Text(
                        p.platform,
                        style: DiaryTheme.product(
                          11,
                          color: DiaryColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}
