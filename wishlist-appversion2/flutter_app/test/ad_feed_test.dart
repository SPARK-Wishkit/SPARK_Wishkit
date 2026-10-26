import 'package:flutter_test/flutter_test.dart';
import 'package:figmadesign/ads/ad_feed.dart';

void main() {
  /// 목록을 'P0 P1 … AD …' 모양으로 펼쳐 본다.
  List<String> layout(int items, int every) {
    final feed = AdFeed(items, every: every);
    return [
      for (var i = 0; i < feed.length; i++)
        feed.isAd(i) ? 'AD${feed.adSlot(i)}' : 'P${feed.itemIndex(i)}',
    ];
  }

  test('6개마다 광고 1칸, 상품 순서는 그대로', () {
    expect(layout(13, 6), [
      'P0', 'P1', 'P2', 'P3', 'P4', 'P5', 'AD0', //
      'P6', 'P7', 'P8', 'P9', 'P10', 'P11', 'AD1', //
      'P12',
    ]);
  });

  test('목록 맨 끝에는 광고를 붙이지 않는다', () {
    expect(layout(12, 6).last, 'P11');
    expect(layout(12, 6).where((e) => e.startsWith('AD')).length, 1);
  });

  test('상품이 간격 이하이면 광고 없음', () {
    expect(layout(6, 6), ['P0', 'P1', 'P2', 'P3', 'P4', 'P5']);
    expect(layout(0, 6), isEmpty);
  });

  test('간격 0이면 광고 없음 (광고 미지원 플랫폼)', () {
    expect(layout(20, 0), [for (var i = 0; i < 20; i++) 'P$i']);
  });

  test('모든 상품이 정확히 한 번씩 나온다', () {
    for (final n in [1, 7, 50, 101]) {
      final items = layout(n, 6).where((e) => e.startsWith('P')).toList();
      expect(items, [for (var i = 0; i < n; i++) 'P$i']);
    }
  });
}
