import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/aws/gql_runner.dart';
import '../../services/parsing_bridge.dart';
import '../../services/share_input.dart';
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

  /// 태그 사진으로 찾았을 때의 결과(어디서 찾았는지 안내용). URL로 직접 읽으면 지운다.
  TagIdentifyResult? tagResult;
  bool identifying = false;

  /// 태그 사진으로 찾았을 때 그 사진. 저장할 때 함께 올려서 상세 페이지에서 다시 볼 수 있게 한다.
  Uint8List? tagPhoto;
  String tagPhotoMime = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    selectedListId = store.tabs
        .firstWhere((t) => t.id != 'all', orElse: () => store.tabs.first)
        .id;
    final initial = widget.sharedUrl ?? store.pendingShareUrl;
    if (initial != null) {
      urlCtrl.text = ShareInput.normalize(initial);
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

  Future<void> _parse({bool fromTag = false}) async {
    final input = urlCtrl.text.trim();
    if (input.isEmpty) return;
    setState(() {
      loading = true;
      error = null;
      if (!fromTag) {
        tagResult = null;
        tagPhoto = null; // URL로 직접 읽으면 앞서 찍은 태그 사진과는 다른 상품일 수 있다.
      }
    });
    try {
      final info = input.contains('http') && !input.trim().contains(' ')
          ? await bridge.parseProductUrl(input)
          : await bridge.scrapShareInput(input);
      titleCtrl.text = info.name == '공유된 상품' ? '' : info.name;
      priceCtrl.text = info.price > 0 ? '${info.price}' : '';
      if (mounted) setState(() => parsed = info);
    } catch (e) {
      if (mounted) setState(() => error = '상품 정보를 읽지 못했어요');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ── 태그 사진으로 찾기 ──

  Future<void> _pickTagPhoto() async {
    if (identifying || loading) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('태그 사진 찍기'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('앨범에서 고르기'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final XFile? picked;
    try {
      // 서버로 보내는 크기를 줄인다 — 태그 글자를 읽기엔 1280px이면 충분하다.
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
    } catch (_) {
      if (mounted) setState(() => error = '카메라나 사진을 열 수 없어요. 권한을 확인해 주세요');
      return;
    }
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    await _identifyFromTag(bytes, _mimeTypeOf(picked));
  }

  String _mimeTypeOf(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.heic') || path.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _identifyFromTag(Uint8List bytes, String mimeType) async {
    final store = context.read<AppStore>();
    setState(() {
      identifying = true;
      error = null;
      tagResult = null;
    });
    TagIdentifyResult result;
    try {
      result = await store.identifyProductFromTag(bytes, mimeType: mimeType);
    } on TagIdentifyUnavailable {
      if (mounted) {
        setState(() {
          identifying = false;
          error = '태그 사진으로 찾기는 로그인 후 사용할 수 있어요';
        });
      }
      return;
    } on AwsDataException catch (e) {
      if (mounted) {
        setState(() {
          identifying = false;
          error = e.isNetwork
              ? e.toString()
              : '사진에서 상품을 찾지 못했어요. 잠시 후 다시 시도해 주세요';
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          identifying = false;
          error = '사진에서 상품을 찾지 못했어요. 잠시 후 다시 시도해 주세요';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      identifying = false;
      tagResult = result;
      tagPhoto = result.status == TagIdentifyStatus.notATag ? null : bytes;
      tagPhotoMime = mimeType;
    });

    switch (result.status) {
      case TagIdentifyStatus.notATag:
        setState(() => error = '상품 태그가 잘 보이게 다시 찍어 주세요');
      case TagIdentifyStatus.found:
        // 가격은 "URL로 담기"와 같은 경로로 읽는다 — 가격 정책이 갈라지지 않게.
        urlCtrl.text = result.matchUrl!;
        await _parse(fromTag: true);
        if (mounted && titleCtrl.text.trim().isEmpty) {
          titleCtrl.text = result.suggestedName;
        }
      case TagIdentifyStatus.notFound:
        final name = result.suggestedName;
        urlCtrl.clear();
        titleCtrl.text = name;
        priceCtrl.text = '';
        setState(() {
          parsed = ParsedProductInfo(
            name: name.isEmpty ? '공유된 상품' : name,
            price: 0,
            platform: result.brand ?? '태그 사진',
            image: '',
            productUrl: '',
            missingFields: const ['price', 'image_url'],
          );
        });
    }
  }

  /// 태그 사진으로 찾은 결과 안내 문구.
  List<String> _tagResultLines(TagIdentifyResult r) {
    final lines = <String>[];
    switch (r.status) {
      case TagIdentifyStatus.found:
        lines.add(
          r.foundOnOfficialSite
              ? '브랜드 공식몰(${r.matchHost})에서 찾았어요'
              : '${r.matchHost}에서 찾았어요 (브랜드 공식몰에서는 확인하지 못했어요)',
        );
        if (r.needsUserCheck) {
          lines.add('품번 없이 이름으로 찾았어요. 같은 상품인지 꼭 확인해 주세요');
        }
      case TagIdentifyStatus.notFound:
        lines.add('태그는 읽었지만 판매 페이지를 찾지 못했어요. 이름과 가격을 직접 입력해 주세요');
        // 서버가 알려 준 이유(예: 시간이 모자람, 품번이 적힌 페이지가 없음) — 다시 시도할지 판단하게.
        final note = r.note?.trim();
        if (note != null && note.isNotEmpty) lines.add('이유: $note');
      case TagIdentifyStatus.notATag:
        break;
    }
    if (r.productCode != null) lines.add('품번 ${r.productCode}');
    if (r.tagPrice != null) {
      lines.add('태그 가격 ${formatWon(r.tagPrice!)} (정가라서 지금 판매가와 다를 수 있어요)');
    }
    return lines;
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
      // 페이지에서 주소를 못 얻었으면 입력칸의 첫 URL 만 쓴다(입력칸 글 전체를 넣지 않는다).
      productUrl: parsed!.productUrl.isEmpty
          ? (ShareInput.firstUrl(urlCtrl.text) ?? urlCtrl.text.trim())
          : parsed!.productUrl,
      originalPrice: parsed!.originalPrice,
      discount: parsed!.discount,
      missingFields: [if (parsed!.image.isEmpty) 'image_url'],
      engineUsed: parsed!.engineUsed,
      purchasePriceStatus: parsed!.purchasePriceStatus,
      priceConfidence: parsed!.priceConfidence,
      extractFailureReason: parsed!.extractFailureReason,
    );

    setState(() {
      saving = true;
      error = null;
    });
    try {
      final store = context.read<AppStore>();
      // 태그 사진이 있으면 먼저 올린다. 실패해도 상품은 저장하고, 사진만 빠졌다고 알려 준다.
      String? tagImageUrl;
      var tagPhotoFailed = false;
      final photo = tagPhoto;
      if (photo != null) {
        try {
          tagImageUrl = await store.uploadTagPhoto(photo, mimeType: tagPhotoMime);
        } catch (_) {
          tagPhotoFailed = true;
        }
      }
      final Product? product;
      try {
        product = await store.addParsedProduct(
          info,
          listId: selectedListId!,
          memo: memoCtrl.text,
          tagImageUrl: tagImageUrl,
        );
      } catch (_) {
        // 상품 저장이 실패하면 방금 올린 태그 사진은 쓸 곳이 없으니 지운다.
        if (tagImageUrl != null) await store.discardTagPhoto(tagImageUrl);
        rethrow;
      }
      if (product == null) {
        // 같은 상품을 이미 저장하는 중(연타) — 이번에 올린 사진은 쓰이지 않는다.
        if (tagImageUrl != null) await store.discardTagPhoto(tagImageUrl);
        return;
      }
      store.setPendingShareUrl(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tagPhotoFailed
                  ? '${product.name} 을(를) 저장했어요. 태그 사진은 저장하지 못했어요'
                  : '${product.name} 을(를) 저장했어요',
            ),
          ),
        );
        context.go('/');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _statusText(ParsedProductInfo info) {
    switch (info.extractFailureReason) {
      case ExtractFailureReason.notLoggedIn:
        return '로그인하면 상품 정보를 자동으로 읽어요. 지금은 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.engineOff:
        return '지금은 자동 읽기 서버가 꺼져 있어요. 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.timeout:
        return '페이지를 읽는 데 시간이 너무 걸렸어요. 다시 시도하거나 직접 입력해 주세요.';
      case ExtractFailureReason.network:
        return '인터넷 연결을 확인해 주세요. 이름과 가격은 직접 입력할 수 있어요.';
      case ExtractFailureReason.failed:
        return '이 페이지는 자동으로 읽지 못했어요. 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.ambiguous:
        return '가격이 여러 개라 확실하지 않아요. 가격을 직접 입력해 주세요.';
      default:
        return info.needsManualPrice ? '가격을 직접 입력해 주세요' : 'AI로 읽음';
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
                      onPressed: loading || identifying ? null : _parse,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DiaryButton(
                  label: loading ? '상품 페이지를 읽는 중...' : '상품 읽기',
                  filled: true,
                  color: DiaryColors.folderBlue,
                  onPressed: loading || identifying ? () {} : _parse,
                ),
                const SizedBox(height: 8),
                DiaryButton(
                  label: identifying
                      ? '태그를 읽고 판매 페이지를 찾는 중... (최대 30초)'
                      : '태그 사진으로 찾기',
                  icon: Icons.photo_camera_outlined,
                  onPressed: loading || identifying ? null : _pickTagPhoto,
                ),
                if (tagResult != null &&
                    tagResult!.status != TagIdentifyStatus.notATag) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DiaryColors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DiaryColors.ink.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tagPhoto != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              tagPhoto!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in _tagResultLines(tagResult!))
                                Text(
                                  line,
                                  style: DiaryTheme.body(
                                    12,
                                    color: DiaryColors.inkMuted,
                                  ),
                                ),
                              if (tagPhoto != null)
                                Text(
                                  '저장하면 태그 사진도 함께 저장돼요 (나만 볼 수 있어요)',
                                  style: DiaryTheme.body(
                                    11,
                                    color: DiaryColors.inkSoft,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
