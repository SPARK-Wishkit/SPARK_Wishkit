import '../models/models.dart';
import 'aws/engine_store.dart';
import 'share_input.dart';
import 'webview_scraper.dart';

typedef OnDeviceExtractFn = Future<OnDeviceExtract?> Function(String url);

/// 공유된 상품 URL을 읽는다. 엔진(AI 추출 서버)이 켜져 있고 주입돼 있으면 먼저 그쪽을
/// 시도하고, 확정 가격을 못 주면(예외·타임아웃·ambiguous·미지원 통화 포함) 단말
/// WebView로 그대로 폴백한다 — 기본값(ENGINE_ENABLED 꺼짐)에서는 지금까지와 동일하게
/// WebView만 쓴다.
///
/// 가격을 못 읽어도 이름·사진·URL은 남기고, 가격은 사용자가 입력한다.
class ParsingBridge {
  ParsingBridge({
    WebViewScraper? webViewScraper,
    OnDeviceExtractFn? extract,
    EngineClient? engine,
  }) : _webView = webViewScraper ?? WebViewScraper(),
       _extract = extract,
       _engine = engine;

  final WebViewScraper _webView;
  final OnDeviceExtractFn? _extract;
  final EngineClient? _engine;

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
    if (url.isNotEmpty && _engine != null) {
      final engineExtract = await _tryEngine(url);
      if (engineExtract != null) {
        return productFromOnDeviceExtract(
          url: url,
          extract: engineExtract,
          titleHint: titleHint,
          engineUsed: true,
        );
      }
    }

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

  /// 엔진을 불러 확정 가격(price>0)을 얻으면 그 결과를, 그 외(예외·타임아웃·ambiguous·
  /// 미지원 통화 등 가격을 못 준 모든 경우)엔 null을 돌려준다 — 호출부는 null이면
  /// WebView로 폴백한다. 엔진 쪽 문제가 사용자 화면까지 새어 나가지 않는다.
  Future<OnDeviceExtract?> _tryEngine(String url) async {
    try {
      final dto = await _engine!.extract(url);
      final extract = engineResultToOnDeviceExtract(dto);
      final price = extract.price;
      return (price != null && price > 0) ? extract : null;
    } catch (_) {
      return null;
    }
  }
}

/// 엔진 서버 응답 → 기존 OnDeviceExtract 모양으로 바꾸는 순수 함수.
///
/// - unconditionalPrice → price(실제 판매가), regularPrice → originalPrice(할인 전
///   정가) — productFromOnDeviceExtract가 이미 "originalPrice는 price보다 클 때만
///   쓴다"는 규칙을 갖고 있어 그대로 맞는다.
/// - confidence("high"/"medium"/"low")는 priceConfidence와 값 체계가 똑같아 그대로 쓴다.
/// - ambiguous==true면 가격을 비우고 ExtractFailureReason.priceAmbiguous를 남긴다
///   (purchasePriceStatus는 가격이 없을 때 productFromOnDeviceExtract가 결국 'unknown'
///   으로 덮어써서 상관없지만, 여기서도 명시적으로 'unknown'으로 둔다).
/// - 통화가 KRW가 아니면(명시적으로 다른 통화가 찍힌 경우만 — null은 "정보 없음"으로
///   보고 걸러내지 않는다) 가격을 비우고 unsupportedCurrency를 남긴다.
OnDeviceExtract engineResultToOnDeviceExtract(ExtractedProductDto dto) {
  final currency = dto.currency;
  final isUnsupportedCurrency =
      currency != null && currency.toUpperCase() != 'KRW';
  final rawPrice = dto.unconditionalPrice;
  final hasPrice =
      !dto.ambiguous &&
      !isUnsupportedCurrency &&
      rawPrice != null &&
      rawPrice > 0;

  final String? failureReason;
  if (isUnsupportedCurrency) {
    failureReason = ExtractFailureReason.unsupportedCurrency;
  } else if (!hasPrice) {
    failureReason = ExtractFailureReason.priceAmbiguous;
  } else {
    failureReason = null;
  }

  return OnDeviceExtract(
    name: dto.productName,
    price: hasPrice ? rawPrice : null,
    originalPrice: hasPrice ? dto.regularPrice : null,
    image: dto.imageUrl,
    purchasePriceStatus: hasPrice ? 'confirmed' : 'unknown',
    priceConfidence: hasPrice ? (dto.confidence ?? 'unknown') : 'unknown',
    failureReason: failureReason,
  );
}

ParsedProductInfo productFromOnDeviceExtract({
  required String url,
  OnDeviceExtract? extract,
  String? titleHint,
  bool engineUsed = false,
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
    resolvedTier: engineUsed ? 1 : (price > 0 ? 2 : 3),
    engineUsed: engineUsed,
    onDeviceExtracted: !engineUsed && extract?.hasAnything == true,
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
