import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/parsing_bridge.dart';
import 'package:figmadesign/services/webview_scraper.dart';

void main() {
  test('WebView가 이름·사진·가격을 읽으면 그대로 저장 후보가 된다', () async {
    final bridge = ParsingBridge(
      extract: (_) async => OnDeviceExtract(
        name: '올드스쿨',
        price: 57000,
        originalPrice: 95000,
        image: 'https://img.vans.com/oldschool.jpg',
        siteName: 'VANS',
        finalUrl: 'https://www.vans.co.kr/PRODUCT/VN000D6WBOM',
        purchasePriceStatus: 'confirmed',
        priceConfidence: 'medium',
      ),
    );

    final result = await bridge.parseProductUrl(
      'https://www.vans.co.kr/PRODUCT/VN000D6WBOM',
    );

    expect(result.name, '올드스쿨');
    expect(result.price, 57000);
    expect(result.originalPrice, 95000);
    expect(result.image, 'https://img.vans.com/oldschool.jpg');
    expect(result.onDeviceExtracted, isTrue);
    expect(result.engineUsed, isFalse);
    expect(result.needsManualPrice, isFalse);
    expect(result.missingFields, isEmpty);
  });

  test('가격이 없어도 이름·사진·URL은 남기고 수동 입력을 요청한다', () async {
    final bridge = ParsingBridge(
      extract: (_) async => OnDeviceExtract(
        name: '마리떼 티셔츠',
        image: 'https://img.example/shirt.jpg',
        failureReason: ExtractFailureReason.priceAmbiguous,
        looksLikeProductPage: true,
        finalUrl: 'https://marithe-official.com/product/detail.html?product_no=8883',
      ),
    );

    final result = await bridge.parseProductUrl(
      'https://marithe-official.com/product/detail.html?product_no=8883',
    );

    expect(result.name, '마리떼 티셔츠');
    expect(result.price, 0);
    expect(result.image, 'https://img.example/shirt.jpg');
    expect(result.needsManualPrice, isTrue);
    expect(result.missingFields, contains('price'));
    expect(result.extractFailureReason, ExtractFailureReason.priceAmbiguous);
  });

  test('페이지를 못 읽어도 URL과 공유 제목 힌트는 남긴다', () async {
    final bridge = ParsingBridge(
      extract: (_) async => OnDeviceExtract(
        failureReason: ExtractFailureReason.loadingTimeout,
      ),
    );

    final result = await bridge.scrapShareInput(
      '501 오리지널 진 https://levi.co.kr/products/501-original',
    );

    expect(result.productUrl, 'https://levi.co.kr/products/501-original');
    expect(result.name, '501 오리지널 진');
    expect(result.price, 0);
    expect(result.image, isEmpty);
    expect(result.needsManualPrice, isTrue);
    expect(result.extractFailureReason, ExtractFailureReason.loadingTimeout);
    expect(result.engineUsed, isFalse);
  });

  test('파이썬 서버 URL 없이 주입된 추출기만 사용한다', () async {
    var called = false;
    final bridge = ParsingBridge(
      extract: (url) async {
        called = true;
        expect(url, 'https://shop.example/p');
        return OnDeviceExtract(name: '상품', price: 1000);
      },
    );

    await bridge.parseProductUrl('https://shop.example/p');
    expect(called, isTrue);
  });
}
