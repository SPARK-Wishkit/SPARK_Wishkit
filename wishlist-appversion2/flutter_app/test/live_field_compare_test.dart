import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/live_field_compare.dart';

void main() {
  test('엔진 이름에 브랜드가 붙어도 화면 상품명과 같은 상품으로 본다', () {
    expect(
      namesMatch(
        engineName: '[트위]벨리브 골지 폴라 긴팔 니트',
        liveName: '벨리브 골지 폴라 긴팔 니트',
        engineBrand: '트위',
      ),
      isTrue,
    );
    expect(
      namesMatch(
        engineName: 'VANS 올드스쿨',
        liveName: '올드스쿨',
        engineBrand: 'VANS',
      ),
      isTrue,
    );
    expect(
      namesMatch(
        engineName: '[무신사 스탠다드] 컴포트 세미와이드 히든 밴딩 슬랙스',
        liveName: '컴포트 세미와이드 히든 밴딩 슬랙스',
      ),
      isTrue,
    );
  });

  test('전혀 다른 상품명은 같다고 보지 않는다', () {
    expect(
      namesMatch(engineName: '올드스쿨', liveName: '에어 포스 1'),
      isFalse,
    );
  });

  test('따옴표만 달라도 같은 상품명으로 본다', () {
    expect(
      namesMatch(
        engineName: 'ACG 돌로미티 코듀로이 재킷',
        liveName: "ACG '돌로미티' 코듀로이 재킷",
      ),
      isTrue,
    );
  });

  test('가격은 조건 없는 판매가를 그대로 비교한다', () {
    expect(pricesMatch(30400, 30400), isTrue);
    expect(pricesMatch(21280, 30400), isFalse);
    expect(pricesMatch(null, 30400), isFalse);
  });

  test('사진 URL은 쿼리만 달라도 같은 파일로 본다', () {
    expect(
      imagesMatch(
        'https://img.vans.com/image/upload/VN000D6WBOM-HERO.jpg?w=800',
        'https://img.vans.com/image/upload/VN000D6WBOM-HERO.jpg?w=200',
      ),
      isTrue,
    );
    expect(
      imagesMatch(
        'https://img.vans.com/image/upload/VN000D6WBOM-HERO.jpg',
        'https://static.zara.net/photos/other.jpg',
      ),
      isFalse,
    );
  });

  test('이름·가격·사진이 모두 맞으면 allMatch다', () {
    final result = compareLiveFields(
      engineName: '나이키 에어 포스 1 07',
      enginePrice: 134100,
      engineImage: 'https://static.nike.com/a/images/t_default/IH1698-100.png',
      engineBrand: '나이키',
      live: const LiveProductFields(
        name: '에어 포스 1 07',
        price: 134100,
        image: 'https://static.nike.com/a/images/t_default/IH1698-100.png?wid=400',
        brand: '나이키',
      ),
    );
    expect(result.allMatch, isTrue);
  });
}
