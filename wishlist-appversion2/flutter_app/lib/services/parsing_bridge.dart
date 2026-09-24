import '../models/models.dart';
import 'share_input.dart';
import 'webview_scraper.dart';

typedef OnDeviceExtractFn = Future<OnDeviceExtract?> Function(String url);

/// 공유된 상품 URL을 단말 WebView로 읽는다. 파이썬 서버는 호출하지 않는다.
///
/// 가격을 못 읽어도 이름·사진·URL은 남기고, 가격은 사용자가 입력한다.
class ParsingBridge {
  ParsingBridge({WebViewScraper? webViewScraper, OnDeviceExtractFn? extract})
    : _webView = webViewScraper ?? WebViewScraper(),
      _extract = extract;

  final WebViewScraper _webView;
  final OnDeviceExtractFn? _extract;

  Future<ParsedProductInfo> parseProductUrl(String url) {
    final target = ShareInput.firstUrl(url) ?? url.trim();
    return _read(target, titleHint: ShareInput.titleHint(url, target));
  }

  Future<ParsedProductInfo> scrapShareInput(String input) {
    final url = ShareInput.firstUrl(input);
    if (url == null || url.isEmpty) {
      return Future.value(
        productFromOnDeviceExtract(
          url: '',
          titleHint: input.trim(),
        ),
      );
    }
    return _read(url, titleHint: ShareInput.titleHint(input, url));
  }

  Future<ParsedProductInfo> _read(String url, {String? titleHint}) async {
    OnDeviceExtract? extracted;
    if (url.isNotEmpty && (_extract != null || WebViewScraper.isSupported)) {
      try {
        extracted = await (_extract ?? _webView.extract)(url);
      } catch (_) {
        extracted = OnDeviceExtract(
          failureReason: ExtractFailureReason.networkError,
        );
      }
    }
    return productFromOnDeviceExtract(
      url: url,
      extract: extracted,
      titleHint: titleHint,
    );
  }
}

ParsedProductInfo productFromOnDeviceExtract({
  required String url,
  OnDeviceExtract? extract,
  String? titleHint,
}) {
  final extractedName = extract?.name?.trim();
  final hint = titleHint?.trim();
  final name = (extractedName != null && extractedName.isNotEmpty)
      ? extractedName
      : (hint != null && hint.isNotEmpty ? hint : '');
  final extractedPrice = extract?.price;
  final price = (extractedPrice != null && extractedPrice > 0)
      ? extractedPrice
      : 0;
  final original = extract?.originalPrice;
  final image = extract?.image?.trim() ?? '';
  final platform = () {
    final site = extract?.siteName?.trim();
    if (site != null && site.isNotEmpty) return site;
    return platformLabelForUrl(url);
  }();
  final productUrl = () {
    final finalUrl = extract?.finalUrl;
    if (finalUrl != null &&
        finalUrl.startsWith('http') &&
        isSameExtractSite(url, finalUrl)) {
      return finalUrl;
    }
    return url;
  }();
  final missing = <String>[
    if (name.isEmpty) 'title',
    if (price <= 0) 'price',
    if (image.isEmpty) 'image_url',
  ];

  return ParsedProductInfo(
    name: name.isEmpty ? '공유된 상품' : name,
    price: price,
    platform: platform,
    image: image,
    productUrl: productUrl,
    originalPrice: original != null && original > price ? original : null,
    missingFields: missing,
    resolvedTier: price > 0 ? 2 : 3,
    engineUsed: false,
    onDeviceExtracted: extract?.hasAnything == true,
    purchasePriceStatus: price > 0
        ? extract?.purchasePriceStatus ?? 'unknown'
        : 'unknown',
    priceConfidence: price > 0
        ? extract?.priceConfidence ?? 'unknown'
        : 'unknown',
    availability: extract?.availability ?? 'unknown',
    optionDependent: extract?.optionDependent,
    optionPriceMin: extract?.optionPriceMin,
    optionPriceMax: extract?.optionPriceMax,
    priceEvidence: price > 0 ? extract?.priceEvidence ?? const [] : const [],
    extractFailureReason: extract?.failureReason,
  );
}

String platformLabelForUrl(String url) {
  final host = extractHost(url) ?? '';
  if (host.contains('musinsa')) return '무신사';
  if (host.contains('zigzag') || host.contains('kakaostyle')) return '지그재그';
  if (host.contains('29cm')) return '29CM';
  if (host.contains('coupang')) return '쿠팡';
  if (host.contains('wconcept')) return 'W CONCEPT';
  if (host.contains('hmall')) return '현대Hmall';
  if (host.contains('vans')) return '반스';
  if (host.contains('nike')) return '나이키';
  if (host.contains('elandmall')) return '이랜드몰';
  if (host.contains('levi')) return '리바이스';
  if (host.isEmpty) return '쇼핑몰';
  return host;
}
