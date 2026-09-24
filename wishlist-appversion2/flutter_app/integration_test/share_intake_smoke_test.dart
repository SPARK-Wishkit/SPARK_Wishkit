import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/parsing_bridge.dart';
import 'package:figmadesign/services/webview_extract_host.dart';
import 'package:figmadesign/services/webview_scraper.dart';

/// 공유 담기 화면이 쓰는 ParsingBridge 경로만 실기기에서 확인한다.
/// AppStore/Firebase에 저장하지 않는다. 로그인·결제·장바구니 변경 없음.
///
/// 실행:
///   flutter test integration_test/share_intake_smoke_test.dart
///     -d R3CY10LF2HE --no-uninstall
enum _SmokeExpect { autoPrice, manualPrice, keepUrl }

class _SmokeCase {
  const _SmokeCase({
    required this.id,
    required this.mall,
    required this.input,
    required this.expect,
  });

  final String id;
  final String mall;
  final String input;
  final _SmokeExpect expect;
}

const _cases = <_SmokeCase>[
  _SmokeCase(
    id: 'vans-share-text',
    mall: '반스',
    input: '올드스쿨 https://www.vans.co.kr/PRODUCT/VN000D6WBOM',
    expect: _SmokeExpect.autoPrice,
  ),
  _SmokeCase(
    id: 'zara-url',
    mall: 'ZARA',
    input: 'https://www.zara.com/kr/ko/item-p05063701.html',
    expect: _SmokeExpect.manualPrice,
  ),
  _SmokeCase(
    id: 'coupang-url',
    mall: '쿠팡',
    input:
        'https://www.coupang.com/vp/products/6830320694?itemId=15948648483&vendorItemId=83406358948',
    expect: _SmokeExpect.keepUrl,
  ),
];

Future<ParsedProductInfo> _readThroughShareBridge(
  WidgetTester tester,
  String input,
) async {
  final bridge = ParsingBridge();
  var done = false;
  final future = bridge.scrapShareInput(input).whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return future;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('공유 담기 WebView 경로 스모크', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WebViewExtractHost(child: SizedBox.shrink())),
    );
    var readyWait = 0;
    while (WebViewExtractHost.maybeInstance?.isReady != true &&
        readyWait < 50) {
      await tester.pump(const Duration(milliseconds: 200));
      readyWait += 1;
    }
    expect(WebViewExtractHost.maybeInstance, isNotNull);
    expect(WebViewExtractHost.maybeInstance!.isReady, isTrue);
    expect(WebViewScraper.isSupported, isTrue);

    Object? jsProbe;
    try {
      jsProbe = await WebViewExtractHost.maybeInstance!.probeJavascript();
    } catch (error) {
      jsProbe = 'error:$error';
    }
    // ignore: avoid_print
    print('SHARE_INTAKE_JS_PROBE $jsProbe');
    expect(jsProbe, anyOf(equals(2), equals(2.0), equals('2')));

    final results = <Map<String, dynamic>>[];
    for (final item in _cases) {
      // ignore: avoid_print
      print('SHARE_INTAKE_BEGIN ${item.id} ${item.mall}');
      final stopwatch = Stopwatch()..start();
      final info = await _readThroughShareBridge(tester, item.input);
      stopwatch.stop();

      final row = <String, dynamic>{
        'id': item.id,
        'mall': item.mall,
        'input': item.input,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'name': info.name,
        'price': info.price,
        'image': info.image,
        'productUrl': info.productUrl,
        'platform': info.platform,
        'engineUsed': info.engineUsed,
        'onDeviceExtracted': info.onDeviceExtracted,
        'needsManualPrice': info.needsManualPrice,
        'missingFields': info.missingFields,
        'extractFailureReason': info.extractFailureReason,
        'resolvedTier': info.resolvedTier,
      };
      results.add(row);
      // ignore: avoid_print
      print('SHARE_INTAKE_SMOKE_RESULT ${jsonEncode(row)}');

      expect(info.engineUsed, isFalse, reason: '${item.mall} must not call Python');
      expect(info.productUrl, contains('http'), reason: '${item.mall} keeps URL');
      switch (item.expect) {
        case _SmokeExpect.autoPrice:
          expect(info.price, greaterThan(0), reason: '${item.mall} auto-fills price');
          expect(info.name, isNot(anyOf('', '공유된 상품')));
          expect(info.image, isNotEmpty);
          expect(info.needsManualPrice, isFalse);
        case _SmokeExpect.manualPrice:
          expect(info.needsManualPrice, isTrue, reason: '${item.mall} asks for price');
          expect(info.price, 0);
        case _SmokeExpect.keepUrl:
          break;
      }
    }

    binding.reportData = <String, dynamic>{
      'platform': defaultTargetPlatform.name,
      'total': results.length,
      'results': results,
    };
    expect(results, hasLength(_cases.length));
  }, timeout: Timeout.none);
}
