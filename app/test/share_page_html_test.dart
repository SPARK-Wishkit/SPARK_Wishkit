import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/share_page_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final basket = SharedBasket(
    id: 'sb-1',
    title: '지은의 살까말까',
    ownerName: '지은',
    createdAt: DateTime(2026, 8, 17),
    items: [
      Product(
        id: 1,
        listId: 'all',
        name: '<script>alert(1)</script>니트',
        price: 32000,
        originalPrice: 40000,
        image: 'https://example.com/knit.png',
        platform: '테스트몰',
        productUrl: 'https://shop.example.com/item/1',
      ),
      Product(
        id: 2,
        listId: 'all',
        name: '위험한 이미지',
        price: 1000,
        image: 'javascript:alert(1)',
        platform: '악성몰',
        productUrl: 'ftp://files.example.com/x',
      ),
    ],
  );

  test('share page HTML mirrors the in-app basket and escapes untrusted text', () {
    final html = buildSharePageHtml(
      basket: basket,
      expiresAt: DateTime(2026, 9, 14),
    );

    expect(kSharePageTtl, const Duration(days: 28));
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('지은의 살까말까'));
    expect(html, contains('지은 님이 공유한 살까말까 바구니'));
    expect(html, contains('32,000원'));
    expect(html, contains('40,000원'));
    expect(html, contains('2026년 9월 14일까지'));
    expect(html, contains('https://example.com/knit.png'));
    expect(html, contains('https://shop.example.com/item/1'));
    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;니트'));
    expect(html, isNot(contains('javascript:alert(1)')));
    expect(html, isNot(contains('ftp://files.example.com/x')));
  });

  test('safeHttpUrl only allows http(s)', () {
    expect(safeHttpUrl('https://ok.example/a'), 'https://ok.example/a');
    expect(safeHttpUrl('http://ok.example/a'), 'http://ok.example/a');
    expect(safeHttpUrl('javascript:alert(1)'), isNull);
    expect(safeHttpUrl('not a url'), isNull);
    expect(safeHttpUrl(''), isNull);
  });

  test('SharedBasket json keeps hosted page fields', () {
    final shared = basket.copyWith(
      publicPageId: 'page-1',
      publicUrl: 'https://example.com/share.html',
      publicUrlExpiresAt: DateTime(2026, 9, 14),
      memo: '고민 메모',
      threadId: 'sb-1',
    );
    final decoded = SharedBasket.fromJson(shared.toJson());
    expect(decoded.publicPageId, 'page-1');
    expect(decoded.publicUrl, 'https://example.com/share.html');
    expect(decoded.publicUrlExpiresAt, DateTime(2026, 9, 14));
    expect(decoded.memo, '고민 메모');
    expect(decoded.threadId, 'sb-1');
  });
}
