import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/parsing_bridge.dart';

import 'fake_extract_gql.dart';

const _url = 'https://www.vans.co.kr/PRODUCT/VN000D6WBOM';

void main() {
  test('서버 AI가 이름·사진·가격을 읽으면 그대로 저장 후보가 된다', () async {
    final gql = FakeExtractGql(
      (_) => extracted(
        name: '올드스쿨',
        price: 57000,
        regular: 95000,
        image: 'https://img.vans.com/oldschool.jpg',
      ),
    );

    final result = await ParsingBridge(runner: gql).parseProductUrl(_url);

    expect(gql.requestedUrls, [_url]);
    expect(result.name, '올드스쿨');
    expect(result.price, 57000);
    expect(result.originalPrice, 95000);
    expect(result.image, 'https://img.vans.com/oldschool.jpg');
    expect(result.productUrl, _url);
    expect(result.platform, '반스');
    expect(result.engineUsed, isTrue);
    expect(result.priceConfidence, 'high');
    expect(result.purchasePriceStatus, 'confirmed');
    expect(result.needsManualPrice, isFalse);
    expect(result.missingFields, isEmpty);
    expect(result.extractFailureReason, isNull);
  });

  test('AI가 가격을 확신하지 못하면(ambiguous) 가격은 비우고 이유를 남긴다', () async {
    final gql = FakeExtractGql(
      (_) => extracted(name: '마리떼 티셔츠', price: null, ambiguous: true),
    );

    final result = await ParsingBridge(runner: gql).parseProductUrl(_url);

    expect(result.name, '마리떼 티셔츠');
    expect(result.price, 0);
    expect(result.needsManualPrice, isTrue);
    expect(result.missingFields, contains('price'));
    expect(result.extractFailureReason, ExtractFailureReason.ambiguous);
  });

  test('ambiguous인데 가격이 있으면 확신 낮음으로 두어 새로고침 때 사용자에게 묻는다', () async {
    final gql = FakeExtractGql((_) => extracted(price: 30000, ambiguous: true));

    final result = await ParsingBridge(runner: gql).parseProductUrl(_url);

    expect(result.price, 30000);
    expect(result.priceConfidence, 'low');
    expect(result.purchasePriceStatus, 'unknown');
  });

  test('원화가 아니면 가격을 저장하지 않는다', () async {
    final gql = FakeExtractGql((_) => extracted(price: 120, currency: 'USD'));

    final result = await ParsingBridge(runner: gql).parseProductUrl(_url);

    expect(result.price, 0);
    expect(result.needsManualPrice, isTrue);
  });

  test('공유 글의 상품명은 서버가 이름을 못 읽었을 때만 쓴다', () async {
    final gql = FakeExtractGql((_) => extracted(name: null, price: null));

    final result = await ParsingBridge(runner: gql)
        .scrapShareInput('올드스쿨 블랙\n$_url');

    expect(gql.requestedUrls, [_url]);
    expect(result.name, '올드스쿨 블랙');
  });

  test('URL이 없는 공유 글은 서버를 부르지 않는다', () async {
    final gql = FakeExtractGql((_) => fail('부르면 안 됨'));

    final result = await ParsingBridge(runner: gql).scrapShareInput('그냥 메모');

    expect(gql.requestedUrls, isEmpty);
    expect(result.name, '그냥 메모');
    expect(result.productUrl, '');
  });

  test('공유용 짧은 링크는 엔진이 푼 실제 상품 주소로 저장한다', () async {
    const short = 'https://musinsa.onelink.me/PvkC/cw1qxmxp';
    const real = 'https://www.musinsa.com/products/4341120';
    final gql = FakeExtractGql((_) => extracted(productUrl: real, name: '무신사 티셔츠'));

    final result = await ParsingBridge(runner: gql).parseProductUrl('무신사 티셔츠 $short');

    expect(gql.requestedUrls, [short]);
    expect(result.productUrl, real);
    expect(result.platform, '무신사');
  });

  test('엔진이 주소를 안 주면 요청한 주소를 그대로 쓴다', () async {
    final gql = FakeExtractGql((_) => extracted(productUrl: null));

    final result = await ParsingBridge(runner: gql).parseProductUrl(_url);

    expect(result.productUrl, _url);
  });

  group('서버 오류 → 화면 안내 이유', () {
    Future<String?> reasonFor(AwsDataException error) async {
      final gql = FakeExtractGql((_) => throw error);
      final result = await ParsingBridge(runner: gql).parseProductUrl('올드스쿨 $_url');
      // 실패해도 URL·공유 제목은 남긴다
      expect(result.productUrl, _url);
      expect(result.name, '올드스쿨');
      expect(result.engineUsed, isFalse);
      return result.extractFailureReason;
    }

    test('엔진 꺼짐', () async {
      expect(await reasonFor(AwsDataException('ENGINE_UNAVAILABLE')), ExtractFailureReason.engineOff);
      expect(await reasonFor(AwsDataException('ENGINE_NOT_CONFIGURED')), ExtractFailureReason.engineOff);
    });

    test('시간 초과 (Lambda 코드 / AppSync 자체 30초)', () async {
      expect(await reasonFor(AwsDataException('ENGINE_TIMEOUT')), ExtractFailureReason.timeout);
      expect(
        await reasonFor(AwsDataException('Execution timed out.', errorType: 'ExecutionTimeout')),
        ExtractFailureReason.timeout,
      );
    });

    test('로그인 안 됨 / 네트워크 / 그 밖의 실패', () async {
      expect(
        await reasonFor(AwsDataException('Not Authorized to access extractProduct', errorType: 'Unauthorized')),
        ExtractFailureReason.notLoggedIn,
      );
      expect(await reasonFor(AwsDataException('offline', errorType: 'Network')), ExtractFailureReason.network);
      expect(await reasonFor(AwsDataException('ENGINE_ERROR')), ExtractFailureReason.failed);
    });
  });
}
