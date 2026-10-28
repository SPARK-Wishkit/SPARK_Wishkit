import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:figmadesign/data/app_store.dart';
import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/screens/product/product_detail_screen.dart';
import 'package:figmadesign/services/parsing_bridge.dart';

import 'fake_extract_gql.dart';

const _url = 'https://www.musinsa.com/products/4341120';

Product _product({int price = 100000, int? originalPrice, int? discount}) =>
    Product(
      id: 1,
      listId: 'summer',
      name: '클래식 반소매 티셔츠',
      price: price,
      image: 'https://example.com/a.png',
      platform: '무신사',
      originalPrice: originalPrice,
      discount: discount,
      productUrl: _url,
      memo: '고민 중',
      tagImageUrl: 'https://cdn/tag.jpg',
    );

Future<AppStore> _store(
  Map<String, dynamic>? Function() extract, {
  DateTime Function()? clock,
  void Function()? onCall,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = AppStore(
    backendConfigured: false,
    clock: clock,
    parsingBridge: ParsingBridge(
      runner: FakeExtractGql((_) {
        onCall?.call();
        return extract();
      }),
    ),
  );
  await store.init();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('확신 있는 새 가격이면 가격·정가·할인율만 바꾸고 메모는 그대로 둔다', () async {
    final store = await _store(
      () => extracted(name: '다른 이름', price: 80000, regular: 100000),
    );
    store.products = [_product()];

    final result = await store.refreshProductPrice(1);

    expect(result.status, PriceRefreshStatus.updated);
    expect(result.previousPrice, 100000);
    expect(result.newPrice, 80000);
    final p = store.productById(1)!;
    expect(p.price, 80000);
    expect(p.originalPrice, 100000);
    expect(p.discount, 20);
    expect(p.name, '클래식 반소매 티셔츠');
    expect(p.memo, '고민 중');
    expect(p.tagImageUrl, 'https://cdn/tag.jpg');
    expect(store.priceCheckedAt(1), isNotNull);
  });

  test('할인이 끝나면 취소선 정가와 할인 배지도 지운다', () async {
    final store = await _store(
      () => extracted(price: 100000, confidence: 'medium'),
    );
    store.products = [
      _product(price: 80000, originalPrice: 100000, discount: 20),
    ];

    final result = await store.refreshProductPrice(1);

    expect(result.status, PriceRefreshStatus.updated);
    final p = store.productById(1)!;
    expect(p.price, 100000);
    expect(p.originalPrice, isNull);
    expect(p.discount, isNull);
  });

  test('가격을 못 읽으면 기존 가격을 유지한다', () async {
    final store = await _store(
      () => extracted(name: '클래식 반소매 티셔츠', price: null, ambiguous: true),
    );
    store.products = [_product()];

    final result = await store.refreshProductPrice(1);

    expect(result.status, PriceRefreshStatus.failed);
    expect(store.productById(1)!.price, 100000);
    expect(store.priceCheckedAt(1), isNull);
  });

  test('확신이 낮은 가격은 바로 바꾸지 않고 확인을 요청한다', () async {
    final store = await _store(
      () => extracted(price: 55000, confidence: 'low'),
    );
    store.products = [_product()];

    final result = await store.refreshProductPrice(1);

    expect(result.status, PriceRefreshStatus.needsConfirm);
    expect(result.newPrice, 55000);
    expect(store.productById(1)!.price, 100000);

    final applied = await store.applyRefreshedPrice(1, result.info!);
    expect(applied.status, PriceRefreshStatus.updated);
    expect(store.productById(1)!.price, 55000);
  });

  test('같은 가격이면 unchanged, 1분 안에 다시 누르면 쇼핑몰을 다시 읽지 않는다', () async {
    var now = DateTime(2026, 10, 22, 12);
    var calls = 0;
    final store = await _store(
      () => extracted(price: 100000),
      clock: () => now,
      onCall: () => calls++,
    );
    store.products = [_product()];

    expect(
      (await store.refreshProductPrice(1)).status,
      PriceRefreshStatus.unchanged,
    );
    expect(
      (await store.refreshProductPrice(1)).status,
      PriceRefreshStatus.tooSoon,
    );
    expect(calls, 1);

    now = now.add(AppStore.priceRefreshCooldown);
    expect(
      (await store.refreshProductPrice(1)).status,
      PriceRefreshStatus.unchanged,
    );
    expect(calls, 2);
  });

  test('바구니에 담긴 같은 상품도 새 가격으로 바뀐다', () async {
    final store = await _store(
      () => extracted(price: 70000),
    );
    store.products = [_product()];
    await store.addToBasket(store.products.first);

    await store.refreshProductPrice(1);

    expect(store.basket.single.product.price, 70000);
  });

  test('링크가 없는 상품은 새로고침할 수 없다', () async {
    final store = await _store(() => null);
    store.products = [
      Product(
        id: 1,
        listId: 'summer',
        name: '링크 없음',
        price: 1000,
        image: '',
        platform: '',
      ),
    ];

    expect(
      (await store.refreshProductPrice(1)).status,
      PriceRefreshStatus.unavailable,
    );
  });

  test('마지막 확인 시각 문구', () {
    final now = DateTime(2026, 10, 22, 12);
    expect(relativeCheckedLabel(now, now), '방금');
    expect(
      relativeCheckedLabel(now.subtract(const Duration(minutes: 5)), now),
      '5분 전',
    );
    expect(
      relativeCheckedLabel(now.subtract(const Duration(hours: 3)), now),
      '3시간 전',
    );
    expect(
      relativeCheckedLabel(now.subtract(const Duration(days: 2)), now),
      '2일 전',
    );
  });
}
