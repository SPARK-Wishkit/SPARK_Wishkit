import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/models/models.dart';

void main() {
  ParsedProductInfo base({int price = 30400, int? originalPrice = 32000}) {
    return ParsedProductInfo(
      name: '상품',
      price: price,
      originalPrice: originalPrice,
      discount: 5,
      platform: '무신사',
      image: '',
      productUrl: 'https://www.musinsa.com/products/6152461',
      resolvedTier: 2,
    );
  }

  test('화면 검증 가격은 메타데이터 가격을 교체한다', () {
    final result = base().mergeOnDevice(
      price: 25600,
      originalPrice: 32000,
      replacePrice: true,
    );

    expect(result.price, 25600);
    expect(result.originalPrice, 32000);
    expect(result.discount, 20);
  });

  test('정가가 판매가보다 작거나 같으면 정가로 저장하지 않는다', () {
    final result = base().mergeOnDevice(
      price: 32000,
      originalPrice: 30400,
      replacePrice: true,
    );

    expect(result.price, 32000);
    expect(result.originalPrice, isNull);
    expect(result.discount, isNull);
  });

  test('가격 보완 모드에서는 기존의 정상 가격을 덮어쓰지 않는다', () {
    final result = base(
      price: 28000,
    ).mergeOnDevice(price: 25000, originalPrice: 32000);

    expect(result.price, 28000);
    expect(result.originalPrice, 32000);
  });

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
      priceEvidence: const [
        {
          'price_role': 'purchase_price',
          'source': 'rendered-webview',
          'adapter': 'musinsa',
          'field': 'product:price:amount',
        },
      ],
    );

    expect(result.purchasePrice, 30400);
    expect(result.regularPrice, 32000);
    expect(result.purchasePriceStatus, 'confirmed');
    expect(result.priceConfidence, 'high');
    expect(result.engineUsed, isFalse);
    expect(result.priceEvidence.single['adapter'], 'musinsa');
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

  test('검증된 온디바이스 어댑터의 가격 의미와 옵션 범위를 보존한다', () {
    final result = base(price: 0, originalPrice: null).mergeOnDevice(
      price: 30400,
      originalPrice: 32000,
      purchasePriceStatus: 'option_dependent',
      priceConfidence: 'high',
      availability: 'available',
      optionDependent: true,
      optionPriceMin: 30400,
      optionPriceMax: 33400,
      priceEvidence: const [
        {
          'price_role': 'purchase_price',
          'source': 'rendered-webview',
          'adapter': '29cm',
          'field': 'item.sellPrice',
        },
      ],
    );

    expect(result.purchasePriceStatus, 'option_dependent');
    expect(result.priceConfidence, 'high');
    expect(result.availability, 'available');
    expect(result.optionDependent, isTrue);
    expect(result.optionPriceMin, 30400);
    expect(result.optionPriceMax, 33400);
    expect(result.priceEvidence.single['adapter'], '29cm');
  });
}
