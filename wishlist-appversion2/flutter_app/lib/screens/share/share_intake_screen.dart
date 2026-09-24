import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/parsing_bridge.dart';
import '../../services/webview_scraper.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

/// Shown when another app shares a product URL into this app.
class ShareIntakeScreen extends StatefulWidget {
  const ShareIntakeScreen({super.key, this.sharedUrl});

  final String? sharedUrl;

  @override
  State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  final bridge = ParsingBridge();
  final urlCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final memoCtrl = TextEditingController();
  bool loading = false;
  bool saving = false;
  String? error;
  ParsedProductInfo? parsed;
  String? selectedListId;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    selectedListId = store.tabs
        .firstWhere((t) => t.id != 'all', orElse: () => store.tabs.first)
        .id;
    final initial = widget.sharedUrl ?? store.pendingShareUrl;
    if (initial != null) {
      urlCtrl.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    }
  }

  @override
  void dispose() {
    urlCtrl.dispose();
    titleCtrl.dispose();
    priceCtrl.dispose();
    memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final input = urlCtrl.text.trim();
    if (input.isEmpty) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final info = input.contains('http') && !input.trim().contains(' ')
          ? await bridge.parseProductUrl(input)
          : await bridge.scrapShareInput(input);
      titleCtrl.text = info.name == '공유된 상품' ? '' : info.name;
      priceCtrl.text = info.price > 0 ? '${info.price}' : '';
      setState(() => parsed = info);
    } catch (e) {
      setState(() => error = '상품 정보를 읽지 못했어요');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (parsed == null || selectedListId == null || saving) return;
    final name = titleCtrl.text.trim().isEmpty
        ? parsed!.name
        : titleCtrl.text.trim();
    final price =
        int.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (name.isEmpty || name == '공유된 상품') {
      setState(() => error = '상품명을 입력해 주세요');
      return;
    }
    if (price <= 0) {
      setState(() => error = '가격을 입력해 주세요');
      return;
    }

    final info = ParsedProductInfo(
      name: name,
      price: price,
      platform: parsed!.platform,
      image: parsed!.image,
      productUrl: parsed!.productUrl.isEmpty
          ? urlCtrl.text.trim()
          : parsed!.productUrl,
      originalPrice: parsed!.originalPrice,
      discount: parsed!.discount,
      missingFields: [if (parsed!.image.isEmpty) 'image_url'],
      resolvedTier: parsed!.price > 0 ? parsed!.resolvedTier : 3,
      engineUsed: false,
      onDeviceExtracted: parsed!.onDeviceExtracted,
      extractFailureReason: parsed!.extractFailureReason,
    );

    setState(() {
      saving = true;
      error = null;
    });
    try {
      final store = context.read<AppStore>();
      final product = await store.addParsedProduct(
        info,
        listId: selectedListId!,
        memo: memoCtrl.text,
      );
      if (product == null) return;
      store.setPendingShareUrl(null);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${product.name} 을(를) 저장했어요')));
        context.go('/');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _statusText(ParsedProductInfo info) {
    switch (info.extractFailureReason) {
      case ExtractFailureReason.accessBlocked:
        return '이 쇼핑몰은 자동으로 열리지 않아요. 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.loadingTimeout:
      case ExtractFailureReason.scriptTimeout:
      case ExtractFailureReason.networkError:
        return '페이지를 다 읽지 못했어요. 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.unsupportedCurrency:
        return '이 쇼핑몰 통화는 아직 저장하지 않아요. 원 가격을 직접 입력해 주세요.';
      default:
        if (info.price > 0 && info.onDeviceExtracted) return '휴대폰에서 읽음';
        if (info.needsManualPrice) return '가격을 직접 입력해 주세요';
        return '휴대폰에서 읽음';
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final lists = store.tabs.where((t) => t.id != 'all').toList();

    return Scaffold(
      backgroundColor: DiaryColors.canvas,
      appBar: AppBar(
        title: Text('공유 담기', style: DiaryTheme.display(28)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DiaryGridPaper(
            child: ListView(
              children: [
                Text(
                  '다른 앱에서 공유한 링크를\n위시리스트 카드로 정리해요',
                  style: DiaryTheme.body(14, color: DiaryColors.inkMuted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '상품 URL 또는 공유 텍스트',
                    filled: true,
                    fillColor: DiaryColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: loading ? null : _parse,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DiaryButton(
                  label: loading ? '상품 페이지를 읽는 중...' : '상품 읽기',
                  filled: true,
                  color: DiaryColors.folderBlue,
                  onPressed: loading ? () {} : _parse,
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: DiaryTheme.body(12, color: DiaryColors.pin),
                  ),
                ],
                if (parsed != null) ...[
                  const SizedBox(height: 16),
                  WhiteProductCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (parsed!.image.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              parsed!.image,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 72,
                                height: 72,
                                color: DiaryColors.grid,
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parsed!.platform,
                                style: DiaryTheme.body(
                                  12,
                                  color: DiaryColors.inkMuted,
                                ),
                              ),
                              Text(
                                _statusText(parsed!),
                                style: DiaryTheme.body(
                                  11,
                                  color: DiaryColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '상품명',
                      filled: true,
                      fillColor: DiaryColors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: parsed!.needsManualPrice
                          ? '판매가 (직접 입력, 원)'
                          : '기본 판매가 (쿠폰·옵션 제외, 원)',
                      filled: true,
                      fillColor: DiaryColors.white,
                    ),
                  ),
                  if (parsed!.originalPrice != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '정가 ${formatWon(parsed!.originalPrice!)} · '
                      '판매가 ${formatWon(parsed!.price)}',
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '쿠폰은 제외한 기본 판매가예요. 옵션을 선택하면 가격이 달라질 수 있어요.',
                    style: DiaryTheme.body(11, color: DiaryColors.inkMuted),
                  ),
                  if (parsed!.missingFields.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      parsed!.needsManualPrice
                          ? '가격을 직접 입력하면 저장할 수 있어요'
                          : '보완 필요: ${parsed!.missingFields.join(', ')}',
                      style: DiaryTheme.body(12, color: DiaryColors.pin),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '어느 리스트로 보낼까요?',
                    style: DiaryTheme.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tab in lists)
                        ChoiceChip(
                          label: Text(tab.name),
                          selected: selectedListId == tab.id,
                          selectedColor: store.tabColor(tab),
                          onSelected: (_) =>
                              setState(() => selectedListId = tab.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '고민하는 이유',
                    style: DiaryTheme.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: memoCtrl,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: '이 상품을 고민하는 이유를 남겨보세요',
                      filled: true,
                      fillColor: DiaryColors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DiaryButton(
                    label: saving ? '저장하는 중...' : '이 리스트에 저장',
                    filled: true,
                    color: DiaryColors.folderMint,
                    onPressed: saving ? null : _save,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
