import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/models/models.dart';

void main() {
  test('구매가·정가 별칭은 생성자 필드를 그대로 따른다', () {
    final result = ParsedProductInfo(
      name: '상품',
      price: 30400,
      originalPrice: 32000,
      platform: '무신사',
      image: '',
      productUrl: 'https://www.musinsa.com/products/6152461',
      purchasePriceStatus: 'confirmed',
      priceConfidence: 'high',
    );

    expect(result.purchasePrice, 30400);
    expect(result.regularPrice, 32000);
    expect(result.purchasePriceStatus, 'confirmed');
    expect(result.priceConfidence, 'high');
    expect(result.engineUsed, isFalse);
  });

  test('정가만 알면 구매 가격을 정가로 대신 채우지 않는다', () {
    final result = ParsedProductInfo(
      name: '상품',
      price: 0,
      originalPrice: 32000,
      platform: '무신사',
      image: '',
      productUrl: 'https://www.musinsa.com/products/6152461',
      purchasePriceStatus: 'unknown',
    );

    expect(result.purchasePrice, isNull);
    expect(result.regularPrice, 32000);
    expect(result.purchasePriceStatus, 'unknown');
    expect(result.needsManualPrice, isTrue);
  });
}
