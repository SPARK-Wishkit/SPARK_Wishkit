import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:figmadesign/services/webview_extract_host.dart';
import 'package:figmadesign/services/webview_scraper.dart';

class _MallCase {
  const _MallCase(this.mall, this.url, {this.expectedAbstain = false});

  final String mall;
  final String url;
  final bool expectedAbstain;
}

// 실기기에서는 반드시 --no-uninstall 을 붙인다. 기본 flutter test 는
// 종료 시 com.softstudio.wishlist 를 지운다.
// 서버나 앱 병합 계층을 거치지 않고 Android WebView 추출기만 검증한다.
// 기존 가격 의미 감사에서 확인한 대표 상품을 우선 사용하며, guard-only 몰은
// 양수 가격이 아니라 안전한 abstain 여부를 확인한다.
const _cases = <_MallCase>[
  _MallCase(
    '쿠팡',
    'https://www.coupang.com/vp/products/6830320694?itemId=15948648483&vendorItemId=83406358948',
  ),
  _MallCase(
    '네이버 쇼핑',
    'https://shopping.naver.com/catalog/51449387423',
    expectedAbstain: true,
  ),
  _MallCase('11번가', 'https://www.11st.co.kr/products/5932454122'),
  _MallCase('무신사', 'https://www.musinsa.com/products/6558705'),
  _MallCase('W컨셉', 'https://www.wconcept.co.kr/Product/307615241'),
  _MallCase('29CM', 'https://www.29cm.co.kr/products/4058252'),
  _MallCase('FILA', 'https://www.fila.co.kr/products/1100fs262rs11m001490'),
  _MallCase('하고', 'https://www.hago.kr/goods/detail/750307'),
  _MallCase('룩핀', 'https://www.lookpin.co.kr/products/3083865'),
  _MallCase(
    '탑텐',
    'https://topten10.goodwearmall.com/product/MSG2UL2205NVP/detail',
  ),
  _MallCase('무인양품', 'https://mujikorea.co.kr/products/view/1005531'),
  _MallCase(
    '현대Hmall',
    'https://www.hmall.com/md/pda/itemPtc?slitmCd=2060464676',
  ),
  _MallCase('롯데온', 'https://www.lotteon.com/p/product/LO2724337622'),
  _MallCase('미쏘', 'https://mixxo.com/product/detail.html?product_no=12455'),
  _MallCase(
    '데일리쥬',
    'https://dailyjou.com/product/detail.html?product_no=22794',
  ),
  _MallCase('리', 'https://leekorea.co.kr/product/detail.html?product_no=14252'),
  _MallCase(
    '필루미네이트',
    'https://filluminate.com/product/detail.html?product_no=11735',
  ),
  _MallCase(
    '어반스터프',
    'https://urbanstoff.com/product/detail.html?product_no=507',
  ),
  _MallCase('낫포유', 'https://not4u.kr/product/detail.html?product_no=261'),
  _MallCase(
    '인사일런스',
    'https://insilence.co.kr/product/detail.html?product_no=7481',
  ),
  _MallCase('파브레가', 'https://fabregat.kr/product/detail.html?product_no=1038'),
  _MallCase('핫핑', 'https://hotping.co.kr/product/detail.html?product_no=29570'),
  _MallCase(
    '유니클로',
    'https://www.uniqlo.com/kr/ko/products/E486612-000/00?colorDisplayCode=65&sizeDisplayCode=005',
  ),
  _MallCase(
    'SSG',
    'https://www.ssg.com/item/itemView.ssg?itemId=1000571660298',
  ),
  _MallCase(
    '더현대Hi',
    'https://hi.thehyundai.com/product/40B1406274?sectId=1031',
  ),
  _MallCase('에이블리', 'https://mobile.a-bly.com/goods/74156532'),
  _MallCase('지그재그', 'https://zigzag.kr/catalog/products/144255443'),
  _MallCase('KREAM', 'https://kream.co.kr/products/1012767'),
  _MallCase(
    '게스',
    'https://www.guesskorea.com/product/detail.html?product_no=45471',
  ),
  _MallCase(
    '리바이스',
    'https://levi.co.kr/products/501-%EC%98%A4%EB%A6%AC%EC%A7%80%EB%84%90-%EC%A7%84-005010193',
  ),
  _MallCase('반스', 'https://www.vans.co.kr/PRODUCT/VN000D6WBOM'),
  _MallCase(
    '커버낫',
    'https://covernat.co.kr/product/detail.html?product_no=5996',
  ),
  _MallCase(
    '코드그라피',
    'https://code-graphy.com/product/detail.html?product_no=6388',
  ),
  _MallCase('후아유', 'https://whoau.com/product/detail.html?product_no=4852'),
  _MallCase('H&M', 'https://www2.hm.com/ko_kr/productpage.1346684001.html'),
  _MallCase(
    'Gap',
    'https://www.gap.com/browse/product.do?pid=1185082032',
    expectedAbstain: true,
  ),
  _MallCase(
    'Aritzia',
    'https://www.aritzia.com/intl/en/product/airbutter%E2%84%A2-repose-longsleeve/133550.html?color=35023',
  ),
  _MallCase('노이아고', 'https://noirer.com/product/detail.html?product_no=2141'),
  _MallCase('립합', 'https://liphop.com/product/detail.html?product_no=17849'),
  _MallCase(
    '마리떼',
    'https://marithe-official.com/product/detail.html?product_no=8883',
  ),
  _MallCase(
    '마하그리드',
    'https://mahagrid.com/product/detail.html?product_no=3854',
  ),
  _MallCase(
    '비바스튜디오',
    'https://vivastudio.co.kr/product/detail.html?product_no=5485',
  ),
  _MallCase(
    '아모멘토',
    'https://amomento.co/product/button-neck-knit-2colors/1642/',
  ),
  _MallCase(
    '앤더슨벨',
    'https://www.anderssonbell.com/product/detail.html?product_no=10605',
  ),
  _MallCase(
    '예일',
    'https://yaleapparel.co.kr/product/detail.html?product_no=18179',
  ),
  _MallCase('오호라', 'https://ohora.kr/product/detail.html?product_no=2275'),
  _MallCase('위드윤', 'https://withyoon.com/product/detail.html?product_no=19342'),
  _MallCase('육육걸즈', 'https://www.66girls.co.kr/product/1/158101/'),
  _MallCase(
    '파르티멘토',
    'https://partimento.com/product/detail.html?product_no=16516',
  ),
  _MallCase('패션플러스', 'https://www.fashionplus.co.kr/goods/detail/418168398'),
  _MallCase(
    '프롬비기닝',
    'https://frombeginning.co.kr/product/detail.html?product_no=22025',
  ),
  _MallCase(
    'LF몰',
    'https://www.lfmall.co.kr/app/product/K560XX01194',
    expectedAbstain: true,
  ),
  _MallCase(
    'Reformation',
    'https://www.thereformation.com/products/delia-dress/1317591.html',
  ),
  _MallCase(
    '나이키',
    'https://www.nike.com/kr/t/나이키-에어-포스-1-07-남성-신발-qdjlTENZ/IH1698-100',
  ),
  _MallCase(
    '올리브영',
    'https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000260600',
  ),
  _MallCase(
    '퀸잇',
    'https://web.queenit.kr/product/421b849e05731238976b9f01d96c7e31',
  ),
  _MallCase('브랜디', 'https://www.brandi.co.kr/products/158997563'),
  _MallCase(
    'NUGU',
    'https://www.nugu.jp/product/JQTFKT2457',
    expectedAbstain: true,
  ),
  _MallCase('CJ온스타일', 'https://display.cjonstyle.com/p/item/2078847097'),
  _MallCase('4910', 'https://4910.kr/desktop/goods/64333542'),
  _MallCase('SSF샵', 'https://www.ssfshop.com/GOOD-ON/GPCX25041604994/good'),
  _MallCase('ZARA', 'https://www.zara.com/kr/ko/item-p05063701.html'),
  _MallCase(
    'SHEIN',
    'https://kr.shein.com/item-p-427349856.html',
    expectedAbstain: true,
  ),
  _MallCase(
    '이랜드몰',
    'https://www.elandmall.co.kr/i/item?itemNo=2607498077&lowerVendNo=LV25019098',
  ),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const startIndex = int.fromEnvironment(
    'WEBVIEW_AUDIT_START',
    defaultValue: 0,
  );
  const endIndex = int.fromEnvironment('WEBVIEW_AUDIT_END', defaultValue: 64);
  const onlyRaw = String.fromEnvironment('WEBVIEW_AUDIT_ONLY');

  testWidgets('64개 등록 쇼핑몰 Android WebView 대표 상품 감사', (tester) async {
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
    expect(
      WebViewExtractHost.maybeInstance!.isReady,
      isTrue,
      reason: 'InAppWebView 컨트롤러가 생성되어야 감사를 시작한다',
    );
    expect(WebViewScraper.isSupported, isTrue);
    Object? jsProbe;
    try {
      jsProbe = await WebViewExtractHost.maybeInstance!.probeJavascript();
    } catch (error) {
      jsProbe = 'error:$error';
    }
    // ignore: avoid_print
    print('WEBVIEW_JS_PROBE $jsProbe');
    expect(
      jsProbe,
      anyOf(equals(2), equals(2.0), equals('2')),
      reason: 'evaluateJavascript가 동작해야 몰 감사를 시작한다 (got $jsProbe)',
    );
    final results = <Map<String, dynamic>>[];
    final onlyIndices = onlyRaw.isEmpty
        ? const <int>{}
        : onlyRaw
              .split(',')
              .map((value) => int.tryParse(value.trim()))
              .whereType<int>()
              .toSet();

    final boundedEnd = endIndex.clamp(startIndex, _cases.length);
    for (var index = startIndex; index < boundedEnd; index++) {
      if (onlyIndices.isNotEmpty && !onlyIndices.contains(index + 1)) continue;
      final item = _cases[index];
      // ignore: avoid_print
      print('WEBVIEW_AUDIT_BEGIN ${index + 1} ${item.mall}');
      final stopwatch = Stopwatch()..start();
      var timedOut = false;
      var extractDone = false;
      final extractFuture = WebViewScraper()
          .extract(item.url, maxWait: const Duration(seconds: 12))
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              timedOut = true;
              return null;
            },
          )
          .whenComplete(() => extractDone = true);
      while (!extractDone) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final extracted = await extractFuture;
      stopwatch.stop();

      final hasPrice = extracted?.price != null && extracted!.price! > 0;
      final classification = timedOut
          ? 'TIMEOUT'
          : item.expectedAbstain && extracted == null
          ? 'EXPECTED_ABSTAIN'
          : extracted == null
          ? 'NO_RESULT'
          : extracted.blocked
          ? 'BLOCKED'
          : item.expectedAbstain && !hasPrice
          ? 'EXPECTED_ABSTAIN'
          : hasPrice && extracted.image != null && extracted.name != null
          ? 'PASS'
          : hasPrice
          ? 'PARTIAL_MEDIA'
          : extracted.hasAnything
          ? 'PARTIAL_NO_PRICE'
          : 'NO_RESULT';

      final row = <String, dynamic>{
        'index': index + 1,
        'mall': item.mall,
        'url': item.url,
        'expectedAbstain': item.expectedAbstain,
        'timedOut': timedOut,
        'classification': classification,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'name': extracted?.name,
        'image': extracted?.image,
        'price': extracted?.price,
        'originalPrice': extracted?.originalPrice,
        'adapter': extracted?.source['adapter'],
        'purchasePriceStatus': extracted?.purchasePriceStatus,
        'priceConfidence': extracted?.priceConfidence,
        'availability': extracted?.availability,
        'optionDependent': extracted?.optionDependent,
        'optionPriceMin': extracted?.optionPriceMin,
        'optionPriceMax': extracted?.optionPriceMax,
        'blocked': extracted?.blocked,
        'failureReason': extracted?.failureReason,
        'looksLikeProductPage': extracted?.looksLikeProductPage,
        'hasJsonLd': extracted?.hasJsonLd,
        'finalUrl': extracted?.finalUrl,
        'source': extracted?.source,
      };
      results.add(row);
      // 한 줄 JSON은 호스트 로그에서 결과 파일로 변환한다.
      // ignore: avoid_print
      print('WEBVIEW_AUDIT_RESULT ${jsonEncode(row)}');
    }

    final counts = <String, int>{};
    for (final row in results) {
      final key = row['classification'] as String;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    binding.reportData = <String, dynamic>{
      'platform': defaultTargetPlatform.name,
      'total': results.length,
      'counts': counts,
      'results': results,
    };
    // 이 테스트의 실패 판정은 개별 추출 결과가 아니라 러너 자체의 완주 여부다.
    final expectedCount = onlyIndices.isEmpty
        ? boundedEnd - startIndex
        : onlyIndices
              .where((index) => index > startIndex && index <= boundedEnd)
              .length;
    expect(results, hasLength(expectedCount));
  }, timeout: Timeout.none);
}
