import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:figmadesign/services/live_field_compare.dart';
import 'package:figmadesign/services/webview_extract_host.dart';
import 'package:figmadesign/services/webview_scraper.dart';

import 'live_field_compare_catalog.dart';

/// 자동 채움 50몰의 WebView 추출 값과 실제 페이지 확인 값을 비교한다.
/// AppStore/Firebase 저장 없음. --no-uninstall 필수.
///
///   flutter test integration_test/live_field_compare_test.dart
///     -d R3CY10LF2HE --no-uninstall
///     --dart-define=LIVE_COMPARE_MALLS=무신사,반스,나이키
Future<OnDeviceExtract?> _extract(WidgetTester tester, String url) async {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  final isAbly = host == 'a-bly.com' || host.endsWith('.a-bly.com');
  final isAndersson = host.endsWith('anderssonbell.com');
  final is4910 = host == '4910.kr' || host.endsWith('.4910.kr');
  final isAritzia = host.contains('aritzia.com');
  final isOlive = host.contains('oliveyoung.co.kr');
  final maxWait = isAbly
      ? const Duration(seconds: 28)
      : (isAritzia
          ? const Duration(seconds: 45)
          : (isAndersson || is4910
              ? const Duration(seconds: 20)
              : (isOlive
                  ? const Duration(seconds: 20)
                  : const Duration(seconds: 12))));
  final hardTimeout = isAbly
      ? const Duration(seconds: 90)
      : (isAritzia
          ? const Duration(seconds: 100)
          : (isOlive
              ? const Duration(seconds: 70)
              : const Duration(seconds: 45)));
  var done = false;
  final future = WebViewScraper()
      .extract(url, maxWait: maxWait)
      .timeout(
        hardTimeout,
        onTimeout: () => null,
      )
      .whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return future;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const onlyRaw = String.fromEnvironment('LIVE_COMPARE_MALLS');

  testWidgets('PASS 몰 WebView vs 실제 페이지 이름·가격·사진', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: WebViewExtractHost(child: SizedBox.shrink())),
    );
    var readyWait = 0;
    while (WebViewExtractHost.maybeInstance?.isReady != true &&
        readyWait < 50) {
      await tester.pump(const Duration(milliseconds: 200));
      readyWait += 1;
    }
    expect(WebViewExtractHost.maybeInstance?.isReady, isTrue);
    Object? jsProbe;
    try {
      jsProbe = await WebViewExtractHost.maybeInstance!.probeJavascript();
    } catch (error) {
      jsProbe = 'error:$error';
    }
    // ignore: avoid_print
    print('LIVE_COMPARE_JS_PROBE $jsProbe');
    expect(jsProbe, anyOf(equals(2), equals(2.0), equals('2')));

    final only = onlyRaw.isEmpty
        ? const <String>{}
        : onlyRaw.split(',').map((value) => value.trim()).toSet();
    final results = <Map<String, dynamic>>[];

    for (final mall in liveCompareMalls) {
      if (only.isNotEmpty && !only.contains(mall.mall)) continue;
      for (var index = 0; index < mall.products.length; index++) {
        final product = mall.products[index];
        // ignore: avoid_print
        print('LIVE_COMPARE_BEGIN ${mall.mall} ${index + 1} ${product.url}');
        final stopwatch = Stopwatch()..start();
        final extracted = await _extract(tester, product.url);
        stopwatch.stop();

        LiveFieldCompareResult? compared;
        if (product.live != null && extracted != null) {
          compared = compareLiveFields(
            engineName: extracted.name,
            enginePrice: extracted.price,
            engineImage: extracted.image,
            engineBrand: extracted.brand,
            live: LiveProductFields(
              name: product.live!.name,
              price: product.live!.price,
              image: product.live!.image,
              brand: product.live!.brand,
            ),
          );
        }

        String classification;
        if (extracted == null) {
          classification = 'NO_RESULT';
        } else if (product.live == null) {
          classification = 'ENGINE_ONLY';
        } else if (compared!.allMatch) {
          classification = 'MATCH';
        } else {
          classification = [
            if (!compared.nameMatch) 'NAME',
            if (!compared.priceMatch) 'PRICE',
            if (!compared.imageMatch) 'IMAGE',
          ].join('_');
        }

        final row = <String, dynamic>{
          'mall': mall.mall,
          'index': index + 1,
          'url': product.url,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'classification': classification,
          'engineName': extracted?.name,
          'engineBrand': extracted?.brand,
          'enginePrice': extracted?.price,
          'engineImage': extracted?.image,
          'liveName': product.live?.name,
          'livePrice': product.live?.price,
          'liveImage': product.live?.image,
          'nameMatch': compared?.nameMatch,
          'priceMatch': compared?.priceMatch,
          'imageMatch': compared?.imageMatch,
          'failureReason': extracted?.failureReason,
          'finalUrl': extracted?.finalUrl,
        };
        results.add(row);
        // ignore: avoid_print
        print('LIVE_COMPARE_RESULT ${jsonEncode(row)}');
      }
    }

    binding.reportData = <String, dynamic>{
      'platform': defaultTargetPlatform.name,
      'total': results.length,
      'results': results,
    };
    expect(results, isNotEmpty);
  }, timeout: Timeout.none);
}
