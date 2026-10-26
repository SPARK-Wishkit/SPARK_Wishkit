/// 상품 카드 목록 사이에 광고 칸을 끼워 넣을 위치를 계산한다(순수 계산, 위젯 없음).
///
/// [every]개마다 광고 1칸. 예) every=6 → 상품 6개, 광고, 상품 6개, 광고, …
/// - 광고는 상품과 상품 **사이**에만 넣는다. 목록 맨 끝에는 붙이지 않는다.
/// - 상품이 [every]개 이하면 광고가 없다.
/// - [every]가 0 이하면 광고를 넣지 않는다(광고 미지원 플랫폼·테스트).
class AdFeed {
  const AdFeed(this.itemCount, {required this.every});

  final int itemCount;
  final int every;

  int get adCount =>
      every <= 0 || itemCount <= every ? 0 : (itemCount - 1) ~/ every;

  /// ListView의 itemCount로 쓴다.
  int get length => itemCount + adCount;

  /// 목록의 [index] 자리가 광고 칸인지.
  bool isAd(int index) =>
      every > 0 && index < length && (index + 1) % (every + 1) == 0;

  /// 광고 칸이 아닌 [index] 자리에 들어갈 상품의 원래 순번.
  int itemIndex(int index) => every > 0 ? index - index ~/ (every + 1) : index;

  /// 광고 칸 [index]가 몇 번째 광고인지(0부터). 위젯 key로 쓴다.
  int adSlot(int index) => index ~/ (every + 1);
}
