import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/product_extract_js.dart';

void main() {
  test('온디바이스 관리 도메인 61개가 추출 JS에 있다', () {
    const domains = <String>[
      'musinsa.com',
      'wconcept.co.kr',
      '29cm.co.kr',
      'fila.co.kr',
      'hago.kr',
      'lookpin.co.kr',
      'topten10.goodwearmall.com',
      'mujikorea.co.kr',
      'hmall.com',
      'lotteon.com',
      'mixxo.com',
      'dailyjou.com',
      'leekorea.co.kr',
      'filluminate.com',
      'urbanstoff.com',
      'not4u.kr',
      'insilence.co.kr',
      'fabregat.kr',
      'hotping.co.kr',
      'uniqlo.com',
      'ssg.com',
      'hi.thehyundai.com',
      'a-bly.com',
      'zigzag.kr',
      'kream.co.kr',
      'guesskorea.com',
      'levi.co.kr',
      'vans.co.kr',
      'covernat.co.kr',
      'code-graphy.com',
      'whoau.com',
      'hm.com',
      'gap.com',
      'aritzia.com',
      'noirer.com',
      'liphop.com',
      'marithe-official.com',
      'mahagrid.com',
      'vivastudio.co.kr',
      'amomento.co',
      'anderssonbell.com',
      'yaleapparel.co.kr',
      'ohora.kr',
      'withyoon.com',
      '66girls.co.kr',
      'partimento.com',
      'fashionplus.co.kr',
      'frombeginning.co.kr',
      'lfmall.co.kr',
      'thereformation.com',
      'nike.com',
      'oliveyoung.co.kr',
      'queenit.kr',
      'brandi.co.kr',
      'nugu.jp',
      'cjonstyle.com',
      '4910.kr',
      'ssfshop.com',
      'zara.com',
      'shein.com',
      'elandmall.co.kr',
    ];

    for (final domain in domains) {
      expect(productExtractJs, contains("'$domain'"), reason: domain);
    }
  });

  test('Gap과 LF몰은 양수 추출 없이 guard-only를 유지한다', () {
    expect(productExtractJs, contains("if(hostIs('gap.com'))return null"));
    expect(productExtractJs, contains("if(hostIs('lfmall.co.kr'))return null"));
  });

  test('NUGU와 SHEIN은 통화·세션 조건이 해소될 때까지 guard-only다', () {
    expect(
      productExtractJs,
      contains("if(hostIs('nugu.jp')||hostIs('shein.com'))return null"),
    );
  });

  test('반스는 recopick 제목을 상품명으로 우선하고 Hmall·이랜드 상품 URL을 인식한다', () {
    expect(productExtractJs, contains("if(vansTitle) name = vansTitle"));
    expect(productExtractJs, contains('itemPtc|slitmCd='));
    expect(productExtractJs, contains(r'/\/i\/item|itemNo='));
    expect(productExtractJs, contains("return result('elandmall',sale"));
    expect(productExtractJs, contains("'s_price'"));
    expect(productExtractJs, isNot(contains("'final_price + s_price'")));
  });

  test('관리 쇼핑몰은 전용 규칙 실패 시 범용 가격으로 우회하지 않는다', () {
    expect(
      productExtractJs,
      contains('structuredPrice=sitePricing?sitePricing.price:'),
    );
    expect(productExtractJs, contains('(managedSite?null:domPrices.price)'));
    expect(productExtractJs, isNot(contains('price = ld.price*100')));
  });

  test('대표 이미지 URL의 중복 스킴·HTML entity·상대경로를 정규화한다', () {
    expect(productExtractJs, contains('function normalizeUrl(value)'));
    expect(productExtractJs, contains("replace(/&amp;/gi,'&')"));
    expect(productExtractJs, contains("new URL(s,location.href)"));
    expect(
      productExtractJs,
      contains("location.protocol==='https:'&&/^http:\\/\\//i.test(s)"),
    );
  });

  test('상품 범위의 구매 가능 증거만 가격 확인에 사용한다', () {
    expect(productExtractJs, contains('var lookActions=Array.from'));
    expect(
      productExtractJs,
      contains('if(!lookActions.length||lookSoldOut)return null'),
    );
    expect(
      productExtractJs,
      isNot(
        contains(
          "if(/품절/.test(document.body?document.body.innerText:''))return null",
        ),
      ),
    );
    expect(
      productExtractJs,
      contains("return cafe24MetaList('not4u','구매하기')"),
    );
    expect(
      productExtractJs,
      contains("return cafe24MetaList('insilence','구매하기')"),
    );
    expect(productExtractJs, contains("'mixxo.com':['mixxo','구매하기']"));
    expect(productExtractJs, contains("'dailyjou.com':['dailyjou','구매하기']"));
    expect(productExtractJs, contains("'covernat.co.kr':['covernat','CART']"));
    expect(
      productExtractJs,
      contains("'code-graphy.com':['codegraphy','구매하기']"),
    );
    expect(productExtractJs, contains("return result('hotping',hlo,null"));
    expect(
      productExtractJs,
      contains("var visibleName=longest.replace(/_/g,' ')"),
    );
    expect(productExtractJs, contains('접속이 잠시 제한되었습니다'));
    expect(productExtractJs, contains('잠시만 기다려 주세요'));
    // Cafe24 meta+LD: empty availability KRW offer + custom span fallback
    expect(
      productExtractJs,
      contains("fromLd?'product:sale_price:amount + Product.offers[KRW]'"),
    );
    expect(
      productExtractJs,
      contains('var display=shown.length===1?shown[0]:(custom.length===1?custom[0]:null)'),
    );
    expect(
      productExtractJs,
      contains("hostIs('hotping.co.kr')||hostIs('withyoon.com')"),
    );
    expect(productExtractJs, contains('function stripHtmlName(value)'));
    expect(
      productExtractJs,
      contains("hostIs('hago.kr')||hostIs('ssg.com')||hostIs('11st.co.kr')"),
    );
    expect(
      productExtractJs,
      contains('/og_200x200|dev_test/i.test(image)'),
    );
    expect(
      productExtractJs,
      contains('if(!fops.length) fops=[sale];'),
    );
    expect(
      productExtractJs,
      contains('4910은 SSR 시 판매가가 __NEXT_DATA__에만 있고'),
    );
  });
}
