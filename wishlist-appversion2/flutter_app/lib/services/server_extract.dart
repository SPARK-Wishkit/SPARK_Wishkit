import '../models/models.dart';

/// 서버 AI 추출(GraphQL `extractProduct`) 결과를 앱 모델로 바꾸는 순수 함수들.
/// 네트워크·Amplify 를 쓰지 않아 단위 테스트로 바로 확인할 수 있다. 요청은 parsing_bridge.dart.

/// 자동으로 못 읽은 이유. [ParsedProductInfo.extractFailureReason] 에 담겨 화면 안내 문구를 고른다.
class ExtractFailureReason {
  ExtractFailureReason._();

  /// 로그인하지 않음 — 서버 AI 는 로그인 사용자만 부를 수 있다.
  static const notLoggedIn = 'not_logged_in';

  /// 엔진 서버가 꺼져 있거나 백엔드에 연결돼 있지 않음.
  static const engineOff = 'engine_off';

  /// 시간 안에 못 읽음(AppSync 30초 한도).
  static const timeout = 'timeout';

  /// 휴대폰 인터넷 연결 문제.
  static const network = 'network';

  /// 엔진이 페이지를 못 읽음(차단·렌더링 오류 등).
  static const failed = 'failed';

  /// 페이지는 읽었지만 AI 가 가격을 확신하지 못해 비워 둠("틀린 값보다 빈 값").
  static const ambiguous = 'ambiguous';
}

/// 서버 오류를 화면 안내용 이유로 바꾼다. parsing-proxy(handler.ts `ErrorCode`)가 던지는 코드 기준.
String failureReasonFor({
  required String detail,
  bool unauthorized = false,
  bool network = false,
}) {
  if (unauthorized) return ExtractFailureReason.notLoggedIn;
  if (network) return ExtractFailureReason.network;
  final code = detail.trim();
  switch (code) {
    case 'ENGINE_NOT_CONFIGURED':
    case 'ENGINE_UNAVAILABLE':
      return ExtractFailureReason.engineOff;
    case 'ENGINE_TIMEOUT':
      return ExtractFailureReason.timeout;
  }
  // AppSync 자체가 30초에 끊은 경우(Lambda 응답 전) — 코드 없이 이런 문구가 온다.
  if (RegExp('timed? ?out|timeout', caseSensitive: false).hasMatch(code)) {
    return ExtractFailureReason.timeout;
  }
  return ExtractFailureReason.failed;
}

/// `extractProduct` 응답([raw], 실패면 null)을 저장 후보로 바꾼다.
///
/// 못 읽은 칸은 비워 두고 사용자가 직접 입력한다. 이름을 못 읽었으면 공유 글의 제목([titleHint])을 쓴다.
ParsedProductInfo productFromServerExtract({
  required String url,
  Map<String, dynamic>? raw,
  String? titleHint,
  String? failureReason,
}) {
  String text(String key) => (raw?[key] as String?)?.trim() ?? '';
  int positive(String key) {
    final v = raw?[key];
    final n = v is num ? v.round() : 0;
    return n > 0 ? n : 0;
  }

  final ambiguous = raw?['ambiguous'] == true;
  final serverName = text('productName');
  final hint = titleHint?.trim() ?? '';
  final name = serverName.isNotEmpty ? serverName : hint;
  final price = positive('unconditionalPrice');
  final regular = positive('regularPrice');
  final image = text('imageUrl');
  final currency = text('currency');
  final krw = currency.isEmpty || currency.toUpperCase() == 'KRW';
  final usablePrice = krw ? price : 0; // 원화가 아니면 저장하지 않는다(앱은 원 단위만 다룸)
  final confidence = text('confidence');
  // 엔진이 실제로 연 주소(공유용 짧은 링크 → musinsa.com/products/… 등). 없으면 요청한 주소를 그대로 쓴다.
  final resolved = text('productUrl');
  final productUrl =
      Uri.tryParse(resolved)?.hasScheme == true && resolved.startsWith('http') ? resolved : url;

  final reason = failureReason ??
      (usablePrice <= 0 && ambiguous ? ExtractFailureReason.ambiguous : null);

  return ParsedProductInfo(
    name: name.isEmpty ? '공유된 상품' : name,
    price: usablePrice,
    platform: platformLabelForUrl(productUrl),
    image: image,
    productUrl: productUrl,
    originalPrice: krw && regular > usablePrice && usablePrice > 0 ? regular : null,
    missingFields: [
      if (name.isEmpty) 'title',
      if (usablePrice <= 0) 'price',
      if (image.isEmpty) 'image_url',
    ],
    engineUsed: raw != null,
    purchasePriceStatus: usablePrice > 0 && !ambiguous ? 'confirmed' : 'unknown',
    // 가격 새로고침은 high/medium 만 바로 반영한다. AI 가 애매하다고 한 값은 사용자에게 묻는다.
    priceConfidence: usablePrice > 0
        ? (ambiguous ? 'low' : (confidence.isEmpty ? 'unknown' : confidence))
        : 'unknown',
    extractFailureReason: reason,
  );
}

/// 쇼핑몰 이름 표시용. 모르는 곳은 주소의 호스트를 그대로 쓴다.
String platformLabelForUrl(String url) {
  final host = (Uri.tryParse(url.trim())?.host ?? '').toLowerCase();
  const labels = <String, String>{
    'musinsa': '무신사',
    'zigzag': '지그재그',
    'kakaostyle': '지그재그',
    '29cm': '29CM',
    'coupang': '쿠팡',
    'wconcept': 'W CONCEPT',
    'hmall': '현대Hmall',
    'vans': '반스',
    'nike': '나이키',
    'elandmall': '이랜드몰',
    'levi': '리바이스',
  };
  for (final entry in labels.entries) {
    if (host.contains(entry.key)) return entry.value;
  }
  return host.isEmpty ? '쇼핑몰' : host;
}
