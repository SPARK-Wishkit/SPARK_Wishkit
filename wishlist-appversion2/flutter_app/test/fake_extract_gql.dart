import 'package:figmadesign/services/aws/gql_runner.dart';

/// 서버 AI 추출(`extractProduct`)만 흉내 내는 가짜 GraphQL. [respond]가 응답 맵을 주거나 예외를 던진다.
class FakeExtractGql implements GqlRunner {
  FakeExtractGql(this.respond);

  final Map<String, dynamic>? Function(String url) respond;
  final requestedUrls = <String>[];

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) async {
    if (!document.contains('extractProduct')) {
      throw UnsupportedError('extractProduct 외 요청: $document');
    }
    final url = variables['url'] as String;
    requestedUrls.add(url);
    return {'extractProduct': respond(url)};
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) => throw UnsupportedError('mutate 는 쓰지 않음');
}

/// 엔진 응답 한 건. 기본값은 "다 읽음".
Map<String, dynamic> extracted({
  String? productUrl,
  String? name = '상품',
  int? price = 10000,
  int? regular,
  String? image = 'https://img.example/a.jpg',
  bool ambiguous = false,
  String? confidence = 'high',
  String? currency = 'KRW',
}) => {
  'productUrl': productUrl,
  'productName': name,
  'unconditionalPrice': price,
  'regularPrice': regular,
  'currency': currency,
  'imageUrl': image,
  'ambiguous': ambiguous,
  'ambiguityReason': ambiguous ? '가격이 여러 개' : null,
  'confidence': confidence,
};
