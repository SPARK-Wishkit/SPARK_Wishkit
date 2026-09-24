import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/webview_extract_host.dart';
import 'package:figmadesign/services/webview_scraper.dart';

class _FakeClock implements ExtractClock {
  _FakeClock() : _now = DateTime(2026, 8, 16, 16, 0, 0);

  DateTime _now;
  final delays = <Duration>[];

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) async {
    delays.add(duration);
    _now = _now.add(duration);
  }
}

String _extractJson({
  String? name,
  int? price,
  int? originalPrice,
  String? image,
  bool blocked = false,
  bool looksLikeProductPage = true,
  String? adapter,
  String? finalUrl,
  String availability = 'unknown',
  String purchasePriceStatus = 'unknown',
  int? optionPriceMin,
  int? optionPriceMax,
}) {
  return jsonEncode({
    'name': name,
    'price': price,
    'originalPrice': originalPrice,
    'image': image,
    'blocked': blocked,
    'looksLikeProductPage': looksLikeProductPage,
    'finalUrl': finalUrl,
    'availability': availability,
    'purchasePriceStatus': purchasePriceStatus,
    'optionPriceMin': optionPriceMin,
    'optionPriceMax': optionPriceMax,
    'source': {if (adapter != null) 'adapter': adapter},
  });
}

void main() {
  test('온디바이스 v2 가격 의미 필드를 파싱한다', () {
    final result = OnDeviceExtract.fromRaw('''
      {
        "name": "상품",
        "price": 30400,
        "originalPrice": 32000,
        "purchasePriceStatus": "option_dependent",
        "priceConfidence": "high",
        "availability": "available",
        "optionDependent": true,
        "optionPriceMin": 30400,
        "optionPriceMax": 33400,
        "priceEvidence": [
          {
            "price_role": "purchase_price",
            "source": "rendered-webview",
            "adapter": "29cm",
            "field": "item.sellPrice"
          }
        ]
      }
    ''');

    expect(result, isNotNull);
    expect(result!.purchasePriceStatus, 'option_dependent');
    expect(result.priceConfidence, 'high');
    expect(result.optionPriceMin, 30400);
    expect(result.optionPriceMax, 33400);
    expect(result.priceEvidence.single['adapter'], '29cm');
  });

  test('실패 이유를 파싱하고 보존한다', () {
    final result = OnDeviceExtract.fromRaw(
      '{"name":"상품","failureReason":"access_blocked","blocked":true}',
    );
    expect(result, isNotNull);
    expect(result!.failureReason, ExtractFailureReason.accessBlocked);
    expect(result.blocked, isTrue);
  });

  test('리다이렉트와 SPA 주소 변경이 멈춘 뒤에만 추출한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(
      clock: clock,
      settleWindow: const Duration(milliseconds: 600),
      pollInterval: const Duration(milliseconds: 200),
    );
    final evalAt = <DateTime>[];
    final startedAt = clock.now();

    loop.onLoadStart('https://shop.example/a');
    loop.onLoadStop('https://shop.example/b');
    loop.onHistoryUpdate('https://shop.example/c');

    final result = await loop.run(
      requestUrl: 'https://shop.example/a',
      maxWait: const Duration(seconds: 4),
      evaluate: (_) async {
        evalAt.add(clock.now());
        return _extractJson(
          name: '상품',
          price: 10000,
          adapter: 'demo',
          finalUrl: 'https://shop.example/c',
        );
      },
      loadUrl: (_) async {},
    );

    expect(evalAt, isNotEmpty);
    expect(
      evalAt.first.difference(startedAt) >= const Duration(milliseconds: 600),
      isTrue,
    );
    expect(result?.price, 10000);
  });

  test('evaluateJavascript timeout 이후에는 같은 세션에 호출을 중첩하지 않는다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(
      clock: clock,
      scriptTimeout: const Duration(milliseconds: 20),
    );
    loop.onLoadStop('https://shop.example/hang');

    final result = await loop.run(
      requestUrl: 'https://shop.example/hang',
      maxWait: const Duration(seconds: 4),
      evaluate: (_) => Completer<dynamic>().future,
      loadUrl: (_) async {},
    );

    expect(loop.evaluateCount, 1);
    expect(result?.failureReason, ExtractFailureReason.scriptTimeout);
    expect(loop.scriptTimedOut, isTrue);
  });

  test('명시적 접근 차단은 즉시 종료하고 reload 하지 않는다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    var loads = 0;
    loop.onLoadStop('https://shop.example/blocked');

    final result = await loop.run(
      requestUrl: 'https://shop.example/blocked',
      maxWait: const Duration(seconds: 8),
      evaluate: (_) async => _extractJson(
        blocked: true,
        looksLikeProductPage: false,
        finalUrl: 'https://shop.example/blocked',
      ),
      loadUrl: (_) async => loads += 1,
    );

    expect(result?.blocked, isTrue);
    expect(result?.failureReason, ExtractFailureReason.accessBlocked);
    expect(loads, 0);
    expect(loop.reloadCount, 0);
    expect(loop.evaluateCount, 1);
  });

  test('빈 결과에만 제한적으로 1회 reload 한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    var loads = 0;
    loop.onLoadStop('https://shop.example/empty');

    final result = await loop.run(
      requestUrl: 'https://shop.example/empty',
      maxWait: const Duration(seconds: 3),
      evaluate: (_) async => _extractJson(looksLikeProductPage: false),
      loadUrl: (url) async {
        loads += 1;
        loop.onLoadStart(url);
        loop.onLoadStop(url);
      },
    );

    expect(loads, 1);
    expect(loop.reloadCount, 1);
    expect(result?.failureReason, ExtractFailureReason.notProductPage);
  });

  test('품절·가격 충돌·미지원 통화는 reload 하지 않는다', () async {
    Future<int> reloadsFor(String json) async {
      final clock = _FakeClock();
      final loop = WebViewExtractLoop(clock: clock);
      var loads = 0;
      loop.onLoadStop('https://shop.example/x');
      await loop.run(
        requestUrl: 'https://www.gap.com/p/1',
        maxWait: const Duration(milliseconds: 800),
        evaluate: (_) async => json,
        loadUrl: (_) async => loads += 1,
      );
      return loads;
    }

    expect(
      await reloadsFor(
        _extractJson(
          name: '품절',
          availability: 'sold_out',
          image: 'https://x/a',
        ),
      ),
      0,
    );
    expect(
      await reloadsFor(
        _extractJson(
          name: '상품',
          image: 'https://x/a',
          looksLikeProductPage: true,
        ),
      ),
      0,
    );
    expect(
      await reloadsFor(
        _extractJson(
          name: 'Gap item',
          looksLikeProductPage: true,
          finalUrl: 'https://www.gap.com/p/1',
        ),
      ),
      0,
    );
  });

  test('같은 가격 fingerprint가 두 번 연속 일치하면 확정한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onLoadStop('https://shop.example/p');
    var evals = 0;

    final result = await loop.run(
      requestUrl: 'https://shop.example/p',
      maxWait: const Duration(seconds: 8),
      evaluate: (_) async {
        evals += 1;
        return _extractJson(
          name: '상품',
          price: 24800,
          originalPrice: 25800,
          adapter: 'hotping',
          optionPriceMin: 24800,
          optionPriceMax: 25800,
          finalUrl: 'https://shop.example/p',
        );
      },
      loadUrl: (_) async {},
    );

    expect(evals, 2);
    expect(result?.price, 24800);
    expect(result?.failureReason, isNull);
  });

  test('fingerprint가 바뀌면 두 번 연속 같기 전에는 확정하지 않는다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onLoadStop('https://shop.example/p');
    final prices = <int>[10000, 20000, 20000];
    var index = 0;

    final result = await loop.run(
      requestUrl: 'https://shop.example/p',
      maxWait: const Duration(seconds: 8),
      evaluate: (_) async {
        final price = prices[index < prices.length ? index : prices.length - 1];
        index += 1;
        return _extractJson(
          name: '상품',
          price: price,
          adapter: 'demo',
          finalUrl: 'https://shop.example/p',
        );
      },
      loadUrl: (_) async {},
    );

    expect(index, 3);
    expect(result?.price, 20000);
  });

  test('대기 시간이 끝나면 가장 품질 높은 best를 반환한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(
      clock: clock,
      pollInterval: const Duration(milliseconds: 200),
    );
    loop.onLoadStop('https://shop.example/p');
    var evals = 0;

    final result = await loop.run(
      requestUrl: 'https://shop.example/p',
      maxWait: const Duration(milliseconds: 900),
      evaluate: (_) async {
        evals += 1;
        if (evals == 1) {
          return _extractJson(name: '상품', looksLikeProductPage: true);
        }
        return _extractJson(
          name: '상품',
          price: 15900,
          adapter: 'not4u',
          finalUrl: 'https://shop.example/p',
        );
      },
      loadUrl: (_) async {},
    );

    expect(result?.price, 15900);
    expect(evals, lessThan(4));
  });

  test('첫 로드가 없으면 추출을 시도한 뒤 loading_timeout으로 분류한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(
      clock: clock,
      firstLoadTimeout: const Duration(milliseconds: 400),
      pollInterval: const Duration(milliseconds: 200),
    );

    final result = await loop.run(
      requestUrl: 'https://shop.example/slow',
      maxWait: const Duration(seconds: 1),
      evaluate: (_) async => null,
      loadUrl: (_) async {},
    );

    expect(result?.failureReason, ExtractFailureReason.loadingTimeout);
    expect(loop.evaluateCount, greaterThan(0));
    expect(loop.loadWaitTimedOut, isTrue);
  });

  test('네트워크 오류 후 결과가 없으면 network_error로 분류한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onNetworkError();

    final result = await loop.run(
      requestUrl: 'https://shop.example/down',
      maxWait: const Duration(milliseconds: 400),
      evaluate: (_) async => null,
      loadUrl: (_) async {},
    );

    expect(result?.failureReason, ExtractFailureReason.networkError);
  });

  test('상품 페이지인데 가격이 없으면 price_ambiguous로 분류한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onLoadStop('https://shop.example/p');

    final result = await loop.run(
      requestUrl: 'https://shop.example/p',
      maxWait: const Duration(milliseconds: 800),
      evaluate: (_) async => _extractJson(name: '상품', image: 'https://x/a.jpg'),
      loadUrl: (_) async {},
    );

    expect(result?.failureReason, ExtractFailureReason.priceAmbiguous);
    expect(result?.name, '상품');
  });

  test('Gap/NUGU처럼 미지원 통화 호스트는 unsupported_currency로 분류한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onLoadStop('https://www.nugu.jp/product/1');

    final result = await loop.run(
      requestUrl: 'https://www.nugu.jp/product/1',
      maxWait: const Duration(milliseconds: 800),
      evaluate: (_) async => _extractJson(
        name: 'NUGU',
        looksLikeProductPage: true,
        finalUrl: 'https://www.nugu.jp/product/1',
      ),
      loadUrl: (_) async {},
    );

    expect(result?.failureReason, ExtractFailureReason.unsupportedCurrency);
  });

  test('about:blank 로드는 첫 상품 로드로 치지 않는다', () {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onLoadStart('about:blank');
    loop.onLoadStop('about:blank');
    expect(loop.sawFirstLoad, isFalse);
    expect(loop.loading, isFalse);

    loop.onLoadStop('https://www.vans.co.kr/PRODUCT/VN000D6WBOM');
    expect(loop.sawFirstLoad, isTrue);
  });

  test('이전 쇼핑몰 finalUrl 결과는 버리고 요청 호스트만 확정한다', () async {
    final clock = _FakeClock();
    final loop = WebViewExtractLoop(clock: clock);
    loop.onLoadStop('https://www.brandi.co.kr/products/1');

    final result = await loop.run(
      requestUrl: 'https://www.brandi.co.kr/products/1',
      maxWait: const Duration(milliseconds: 800),
      evaluate: (_) async => _extractJson(
        name: '퀸잇 상품',
        price: 12900,
        image: 'https://x/a.jpg',
        finalUrl: 'https://web.queenit.kr/product/old',
      ),
      loadUrl: (_) async {},
    );

    expect(result?.price, isNull);
    expect(result?.name, isNull);
    expect(result?.failureReason, ExtractFailureReason.notProductPage);
  });

  test('같은 사이트의 www/서브도메인은 요청 호스트로 인정한다', () {
    expect(
      isSameExtractSite(
        'https://vans.co.kr/PRODUCT/1',
        'https://www.vans.co.kr/PRODUCT/1',
      ),
      isTrue,
    );
    expect(
      isSameExtractSite(
        'https://a-bly.com/goods/1',
        'https://mobile.a-bly.com/goods/1',
      ),
      isTrue,
    );
    expect(
      isSameExtractSite(
        'https://m.a-bly.com/goods/1',
        'https://mobile.a-bly.com/goods/1',
      ),
      isTrue,
    );
    expect(
      isSameExtractSite(
        'https://www.brandi.co.kr/products/1',
        'https://web.queenit.kr/product/1',
      ),
      isFalse,
    );
    expect(isForeignExtractResult('https://x.example/p', 'about:blank'), isTrue);
    expect(isForeignExtractResult('https://x.example/p', null), isFalse);
  });

  testWidgets('추출 호스트는 트리에 붙으면 인스턴스를 등록한다', (tester) async {
    expect(WebViewExtractHost.maybeInstance, isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: WebViewExtractHost(
          mountWebView: false,
          child: SizedBox.shrink(),
        ),
      ),
    );
    expect(WebViewExtractHost.maybeInstance, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(WebViewExtractHost.maybeInstance, isNull);
  });
}
