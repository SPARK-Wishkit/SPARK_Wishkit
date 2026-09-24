import 'package:figmadesign/services/share_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareInput.firstUrl', () {
    test('accepts a plain URL', () {
      expect(
        ShareInput.firstUrl('https://www.musinsa.com/products/3348384'),
        'https://www.musinsa.com/products/3348384',
      );
    });

    test('finds a URL after a shopping-app message', () {
      const input = '''쿠팡을 추천합니다!
테스트 상품
https://link.coupang.com/a/example''';

      expect(ShareInput.firstUrl(input), 'https://link.coupang.com/a/example');
    });

    test('removes punctuation appended by a sentence', () {
      expect(
        ShareInput.firstUrl('이 상품 어때요? (https://shop.example/item/1).'),
        'https://shop.example/item/1',
      );
    });

    test('rejects text without an HTTP URL', () {
      expect(ShareInput.firstUrl('사진만 공유했어요'), isNull);
      expect(ShareInput.firstUrl(r'C:\temp\product.jpg'), isNull);
    });
  });

  group('ShareInput.fromCandidates', () {
    test('skips an image path and preserves the complete share message', () {
      const message = '에이블리 추천 상품 https://m.a-bly.com/goods/123';

      expect(
        ShareInput.fromCandidates([r'C:\cache\product.jpg', message]),
        message,
      );
    });

    test('returns null for image-only shares', () {
      expect(ShareInput.fromCandidates([r'C:\cache\product.jpg']), isNull);
    });

    test('reads an iOS share-extension title plus URL payload', () {
      const message = '무신사 후드티\nhttps://www.musinsa.com/products/3348384';

      expect(
        ShareInput.fromCandidates([
          message,
          'https://www.musinsa.com/products/3348384',
        ]),
        message,
      );
    });
  });

  group('ShareInput.titleHint', () {
    test('uses text before the URL as a product name hint', () {
      expect(
        ShareInput.titleHint(
          '올드스쿨 https://www.vans.co.kr/PRODUCT/1',
          'https://www.vans.co.kr/PRODUCT/1',
        ),
        '올드스쿨',
      );
    });

    test('returns null when only a URL is shared', () {
      expect(
        ShareInput.titleHint(
          'https://www.vans.co.kr/PRODUCT/1',
          'https://www.vans.co.kr/PRODUCT/1',
        ),
        isNull,
      );
    });
  });
}
