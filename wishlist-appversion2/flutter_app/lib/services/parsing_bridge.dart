import '../models/models.dart';
import 'aws/gql_documents.dart';
import 'aws/gql_runner.dart';
import 'server_extract.dart';
import 'share_input.dart';

export 'server_extract.dart' show ExtractFailureReason, platformLabelForUrl;

/// 상품 URL 을 서버 AI 엔진으로 읽는다.
///
/// 앱 → GraphQL `extractProduct` → Lambda(parsing-proxy) → 엔진 서버 POST /extract
/// (페이지 렌더링 + Gemini 로 이름·가격·사진 추출, 애매하면 화면 캡처를 Gemini 비전으로 다시 읽음).
/// 2026-09-18 "서버 AI 완전 의존" 결정에 따라 단말 WebView 추출기는 2026-10-24 에 제거했다.
///
/// 못 읽어도 예외를 던지지 않는다 — URL·공유 제목은 남기고 이유([ExtractFailureReason])를 담아
/// 돌려주며, 빈 칸은 사용자가 직접 입력한다.
class ParsingBridge {
  ParsingBridge({GqlRunner? runner}) : _gql = runner ?? const AmplifyGqlRunner();

  final GqlRunner _gql;

  /// URL 이나 `상품명 + URL` 공유 글을 읽는다.
  Future<ParsedProductInfo> parseProductUrl(String input) {
    final url = ShareInput.firstUrl(input) ?? input.trim();
    return _read(url, titleHint: ShareInput.titleHint(input, url));
  }

  /// 공유 글을 읽는다. URL 이 없으면 서버를 부르지 않고 글을 상품명 후보로만 쓴다.
  Future<ParsedProductInfo> scrapShareInput(String input) {
    final url = ShareInput.firstUrl(input);
    if (url == null) {
      return Future.value(productFromServerExtract(url: '', titleHint: input.trim()));
    }
    return _read(url, titleHint: ShareInput.titleHint(input, url));
  }

  Future<ParsedProductInfo> _read(String url, {String? titleHint}) async {
    Map<String, dynamic>? raw;
    String? failure;
    try {
      final data = await _gql.query(Gql.extractProduct, variables: {'url': url});
      final result = data['extractProduct'];
      if (result is Map) raw = result.cast<String, dynamic>();
    } on AwsDataException catch (e) {
      failure = failureReasonFor(
        detail: e.debugDetail,
        unauthorized: e.isUnauthorized,
        network: e.isNetwork,
      );
    } catch (_) {
      failure = ExtractFailureReason.failed;
    }
    return productFromServerExtract(
      url: url,
      raw: raw,
      titleHint: titleHint,
      failureReason: failure,
    );
  }
}
