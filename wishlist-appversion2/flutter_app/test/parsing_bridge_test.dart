import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/aws/engine_store.dart';
import 'package:figmadesign/services/parsing_bridge.dart';
import 'package:figmadesign/services/webview_scraper.dart';

/// 테스트용 가짜 EngineClient. [respond]가 예외를 던지면 그대로 전파한다
/// (ParsingBridge가 그 예외를 잡아 폴백하는지 확인하기 위함).
class _FakeEngineClient implements EngineClient {
  _FakeEngineClient(this.respond);

  final Future<ExtractedProductDto> Function(String url) respond;
  int callCount = 0;

  @override
  Future<ExtractedProductDto> extract(String url) {
    callCount++;
    return respond(url);
  }
}

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

  group('엔진(AI 추출 서버) 연동', () {
    test('기능 플래그 기본값은 꺼짐이다', () {
      expect(kEngineEnabled, isFalse);
    });

    test(
      '플래그가 꺼져 있으면(실제 주입 지점과 같은 패턴) 엔진은 한 번도 호출되지 않는다',
      () async {
        // share_intake_screen.dart와 동일한 패턴: kEngineEnabled가 false면
        // engine 자체가 null로 주입된다.
        final spyEngine = _FakeEngineClient(
          (_) async => throw StateError('엔진이 호출되면 안 됨'),
        );
        final bridge = ParsingBridge(
          engine: kEngineEnabled ? spyEngine : null,
          extract: (_) async => OnDeviceExtract(name: '웹뷰상품', price: 1000),
        );

        final result = await bridge.parseProductUrl('https://shop.example/p');

        expect(spyEngine.callCount, 0);
        expect(result.engineUsed, isFalse);
        expect(result.price, 1000);
      },
    );

    test('엔진이 확정 가격을 주면 그걸로 결과를 만들고 WebView는 호출하지 않는다', () async {
      var webViewCalled = false;
      final engine = _FakeEngineClient(
        (_) async => const ExtractedProductDto(
          productName: '무신사 반소매',
          unconditionalPrice: 29000,
          regularPrice: 39000,
          currency: 'KRW',
          imageUrl: 'https://img.example/x.jpg',
          ambiguous: false,
          confidence: 'high',
        ),
      );
      final bridge = ParsingBridge(
        engine: engine,
        extract: (_) async {
          webViewCalled = true;
          return OnDeviceExtract(name: '웹뷰상품', price: 1);
        },
      );

      final result = await bridge.parseProductUrl(
        'https://www.musinsa.com/products/1',
      );

      expect(result.engineUsed, isTrue);
      expect(result.resolvedTier, 1);
      expect(result.name, '무신사 반소매');
      expect(result.price, 29000);
      expect(result.originalPrice, 39000);
      expect(result.image, 'https://img.example/x.jpg');
      expect(result.onDeviceExtracted, isFalse);
      expect(webViewCalled, isFalse);
      expect(engine.callCount, 1);
    });

    test('엔진이 ambiguous면(가격 없음) WebView로 폴백한다', () async {
      final engine = _FakeEngineClient(
        (_) async => const ExtractedProductDto(
          productName: null,
          unconditionalPrice: null,
          ambiguous: true,
          confidence: 'low',
        ),
      );
      final bridge = ParsingBridge(
        engine: engine,
        extract: (_) async => OnDeviceExtract(
          name: '웹뷰상품',
          price: 15000,
          purchasePriceStatus: 'confirmed',
          priceConfidence: 'high',
        ),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.engineUsed, isFalse);
      expect(result.name, '웹뷰상품');
      expect(result.price, 15000);
    });

    test('엔진 호출이 예외를 던지면 폴백하고 예외가 밖으로 새지 않는다', () async {
      final engine = _FakeEngineClient(
        (_) async => throw Exception('network down'),
      );
      final bridge = ParsingBridge(
        engine: engine,
        extract: (_) async => OnDeviceExtract(name: '웹뷰상품', price: 8000),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.engineUsed, isFalse);
      expect(result.price, 8000);
    });

    test('엔진 호출이 타임아웃되면(TimeoutException) 폴백한다', () async {
      final engine = _FakeEngineClient(
        (_) async => throw TimeoutException('engine timeout'),
      );
      final bridge = ParsingBridge(
        engine: engine,
        extract: (_) async => OnDeviceExtract(name: '웹뷰상품', price: 5000),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.engineUsed, isFalse);
      expect(result.price, 5000);
    });

    test('통화가 KRW가 아니면 가격을 쓰지 않고 WebView로 폴백한다', () async {
      final engine = _FakeEngineClient(
        (_) async => const ExtractedProductDto(
          productName: '해외 상품',
          unconditionalPrice: 100,
          regularPrice: 120,
          currency: 'USD',
          imageUrl: 'https://img.example/y.jpg',
          ambiguous: false,
          confidence: 'high',
        ),
      );
      final bridge = ParsingBridge(
        engine: engine,
        extract: (_) async => OnDeviceExtract(name: '웹뷰상품', price: 3000),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.engineUsed, isFalse);
      expect(result.price, 3000);
    });

    test('엔진·WebView 둘 다 가격을 못 읽으면 기존처럼 수동 입력으로 남는다', () async {
      final engine = _FakeEngineClient(
        (_) async => const ExtractedProductDto(ambiguous: true),
      );
      final bridge = ParsingBridge(
        engine: engine,
        extract: (_) async => OnDeviceExtract(
          name: '상품',
          failureReason: ExtractFailureReason.priceAmbiguous,
        ),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.engineUsed, isFalse);
      expect(result.needsManualPrice, isTrue);
      expect(result.resolvedTier, 3);
    });
  });

  group('엔진 결과 보충(WebView, 최대 8초)', () {
    EngineClient engineWith({String? name, String? image}) =>
        _FakeEngineClient(
          (_) async => ExtractedProductDto(
            productName: name,
            unconditionalPrice: 10000,
            regularPrice: 12000,
            currency: 'KRW',
            imageUrl: image,
            ambiguous: false,
            confidence: 'high',
          ),
        );

    test('이미지만 비어 있으면 WebView로 이미지만 채운다(가격은 엔진 값 유지)', () async {
      final bridge = ParsingBridge(
        engine: engineWith(name: '엔진상품', image: null),
        extract: (_) async => OnDeviceExtract(
          name: '웹뷰상품',
          image: 'https://img.example/webview.jpg',
          price: 99999,
        ),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.name, '엔진상품');
      expect(result.image, 'https://img.example/webview.jpg');
      expect(result.price, 10000);
      expect(result.engineUsed, isTrue);
      expect(result.onDeviceExtracted, isFalse);
    });

    test('이름만 비어 있으면 WebView로 이름만 채운다(이미지는 엔진 값 유지)', () async {
      final bridge = ParsingBridge(
        engine: engineWith(name: null, image: 'https://img.example/engine.jpg'),
        extract: (_) async => OnDeviceExtract(
          name: '웹뷰상품',
          image: 'https://img.example/webview-ignored.jpg',
        ),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.name, '웹뷰상품');
      expect(result.image, 'https://img.example/engine.jpg');
      expect(result.engineUsed, isTrue);
      expect(result.onDeviceExtracted, isFalse);
    });

    test('이름·이미지가 둘 다 있으면 WebView를 호출하지 않는다', () async {
      var webViewCalled = false;
      final bridge = ParsingBridge(
        engine: engineWith(
          name: '엔진상품',
          image: 'https://img.example/engine.jpg',
        ),
        extract: (_) async {
          webViewCalled = true;
          return OnDeviceExtract(name: '웹뷰상품', image: 'https://img.example/x.jpg');
        },
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(webViewCalled, isFalse);
      expect(result.name, '엔진상품');
      expect(result.image, 'https://img.example/engine.jpg');
    });

    test('WebView 보충이 실패해도 엔진 결과를 그대로 쓴다(예외가 새지 않음)', () async {
      final bridge = ParsingBridge(
        engine: engineWith(name: null, image: null),
        extract: (_) async => throw Exception('webview down'),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.price, 10000);
      expect(result.engineUsed, isTrue);
      expect(result.missingFields, containsAll(['title', 'image_url']));
    });

    test('WebView가 다른 가격·원가를 줘도 엔진 가격·원가를 그대로 유지한다', () async {
      final bridge = ParsingBridge(
        engine: engineWith(name: null, image: null),
        extract: (_) async => OnDeviceExtract(
          name: '웹뷰상품',
          image: 'https://img.example/webview.jpg',
          price: 1,
          originalPrice: 2,
        ),
      );

      final result = await bridge.parseProductUrl('https://shop.example/p');

      expect(result.name, '웹뷰상품');
      expect(result.image, 'https://img.example/webview.jpg');
      expect(result.price, 10000);
      expect(result.originalPrice, 12000);
    });
  });
}
