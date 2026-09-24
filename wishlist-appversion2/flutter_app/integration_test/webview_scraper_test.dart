// Tier 2.5 검증 — 실기기/에뮬레이터에서 WebViewScraper 가 실제로
// 상품 페이지를 열어 가격을 뽑아내는지 확인한다.
//
// 실행 (에뮬레이터 켜진 상태):
//   flutter test integration_test/webview_scraper_test.dart -d emulator-5554
//
// 로그인·엔진 서버·UI 없이 WebViewScraper 만 직접 호출하므로,
// 이 테스트가 통과하면 Android 빌드 + inappwebview 네이티브 + Tier 2.5 추출이
// 모두 정상이라는 뜻이다.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:figmadesign/services/webview_extract_host.dart';
import 'package:figmadesign/services/webview_scraper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('WebViewScraper (Tier 2.5)', () {
    test('지원 플랫폼 여부', () {
      // Android/iOS 에서만 true. 이 테스트는 에뮬레이터에서 도는 걸 전제로 한다.
      debugPrint('WebViewScraper.isSupported = ${WebViewScraper.isSupported}');
      expect(WebViewScraper.isSupported, isTrue);
    });

    // 몰별로 서버가 못 얻는 것을 단말이 채우는지 확인.
    // - 무신사: JSON-LD 늦게 삽입
    // - 무인양품: JSON-LD 없음 → 화면 DOM
    // - 자라: ProductGroup + ÷100 보정
    final cases = <String, String>{
      '무신사': 'https://www.musinsa.com/products/3348384',
      '무인양품': 'https://mujikorea.co.kr/products/view/1005528',
    };

    cases.forEach((label, url) {
      testWidgets('$label 에서 가격 추출', (tester) async {
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
        final scraper = WebViewScraper();
        final result = await scraper.extract(
          url,
          maxWait: const Duration(seconds: 20),
        );

        debugPrint(
          '[$label] name=${result?.name} '
          'price=${result?.price} '
          'source=${result?.source} '
          'hasJsonLd=${result?.hasJsonLd}',
        );

        expect(result, isNotNull, reason: '$label 추출 결과가 null 이면 안 됨');
        expect(result!.name, isNotNull, reason: '$label 상품명 필요');
        expect(result.price, isNotNull, reason: '$label 가격 추출 실패');
        expect(result.price! > 0, isTrue);
      });
    });
  });
}
