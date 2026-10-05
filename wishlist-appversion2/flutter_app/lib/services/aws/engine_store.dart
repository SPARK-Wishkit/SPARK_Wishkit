import 'gql_documents.dart';
import 'gql_runner.dart';

/// AI 추출 엔진 서버(parsing-engine) 연동 기능 플래그. 기본 꺼짐 — 켜려면 빌드·실행 시
/// `--dart-define=ENGINE_ENABLED=true`를 넘긴다. 꺼져 있으면 ParsingBridge는 지금까지와
/// 똑같이 단말 WebView(Tier 2.5)만 쓴다.
const bool kEngineEnabled = bool.fromEnvironment(
  'ENGINE_ENABLED',
  defaultValue: false,
);

/// 엔진 서버(POST /extract)의 실제 응답을 그대로 옮긴 모양.
/// amplify/data/resource.ts의 ExtractedProduct, parsing-engine/server/main.py
/// `_extract()`와 필드가 1:1로 맞아야 한다.
class ExtractedProductDto {
  const ExtractedProductDto({
    this.productName,
    this.unconditionalPrice,
    this.regularPrice,
    this.currency,
    this.imageUrl,
    this.ambiguous = true,
    this.ambiguityReason,
    this.confidence,
  });

  final String? productName;
  final int? unconditionalPrice;
  final int? regularPrice;
  final String? currency;
  final String? imageUrl;
  final bool ambiguous;
  final String? ambiguityReason;
  final String? confidence;

  factory ExtractedProductDto.fromJson(Map<String, dynamic> json) {
    return ExtractedProductDto(
      productName: json['productName'] as String?,
      unconditionalPrice: (json['unconditionalPrice'] as num?)?.toInt(),
      regularPrice: (json['regularPrice'] as num?)?.toInt(),
      currency: json['currency'] as String?,
      imageUrl: json['imageUrl'] as String?,
      ambiguous: json['ambiguous'] as bool? ?? true,
      ambiguityReason: json['ambiguityReason'] as String?,
      confidence: json['confidence'] as String?,
    );
  }
}

/// 앱↔엔진 호출 인터페이스. 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class EngineClient {
  Future<ExtractedProductDto> extract(String url);
}

/// AppSync(extractProduct 쿼리)를 거쳐 엔진 서버를 호출하는 구현.
///
/// 엔진 서버 자체는 VPC 프라이빗 서브넷에 있어 이 경로로만 접근할 수 있다 — 로그인
/// 사용자만 호출 가능하므로(GqlAuth.user), 비로그인 상태에서는 엔진을 쓸 수 없다.
class AppSyncEngineClient implements EngineClient {
  AppSyncEngineClient(this._gql, {this.timeout = const Duration(seconds: 27)});

  final GqlRunner _gql;

  /// AppSync 30초 하드 리밋(조정 불가)보다 살짝 짧게 — 체인: 엔진 EXTRACT_TIMEOUT_S
  /// 22초(배포 env) < Lambda fetch 중단 25초 < Lambda timeoutSeconds 28초 <
  /// AppSync 30초. 앱은 그 30초보다 먼저 포기해서 사용자에게 "너무 오래 걸림"
  /// 메시지를 AppSync 자체 타임아웃 오류보다 먼저 보여준다.
  final Duration timeout;

  @override
  Future<ExtractedProductDto> extract(String url) async {
    final data = await _gql
        .query(Gql.extractProduct, variables: {'url': url}, auth: GqlAuth.user)
        .timeout(timeout);
    final raw = data['extractProduct'];
    if (raw is! Map) {
      throw const FormatException('엔진 서버 응답이 비어 있습니다.');
    }
    return ExtractedProductDto.fromJson(raw.cast<String, dynamic>());
  }
}
