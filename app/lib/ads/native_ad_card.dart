import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/diary_theme.dart';
import '../theme/list_card.dart';
import 'ads_config.dart';

/// 상품 카드 사이에 들어가는 광고 카드.
///
/// 크기·모서리·그림자는 상품 카드와 같게(ListCardMetrics) 맞추고, 바탕만 한 톤 어두운 회색으로 둔다.
/// AdMob 정책상 광고는 앱 콘텐츠와 분명히 구분돼야 한다 — 회색 바탕과 템플릿의 "Ad" 표시(AdMob 이
/// 요구하는 광고 표시)를 상품 카드처럼 바꾸지 말 것.
///
/// 광고를 못 불러오면(네트워크·광고 없음) 칸을 통째로 없앤다 — 빈 회색 박스를 남기지 않는다.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  /// 상품 카드(흰색)보다 한 톤 어두운, 눈에 덜 띄는 회색.
  static const background = Color(0xFFEDEDED);

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _loaded = false;

  // 스크롤로 화면 밖에 나갔다 돌아올 때마다 광고를 새로 불러오지 않게 살려 둔다.
  @override
  bool get wantKeepAlive => _ad != null;

  @override
  void initState() {
    super.initState();
    if (!AdsConfig.supported) return;
    _ad = NativeAd(
      adUnitId: AdsConfig.nativeUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: NativeAdCard.background,
        cornerRadius: ListCardMetrics.radius,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: DiaryColors.inkSoft,
          style: NativeTemplateFontStyle.bold,
          size: 13,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: DiaryColors.inkMuted,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: DiaryColors.inkSoft,
          size: 12,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: DiaryColors.inkSoft,
          size: 11,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          if (mounted) {
            setState(() => _loaded = false);
            updateKeepAlive();
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    // 광고 화면(AdWidget)은 자기 크기가 없어 주어진 최대 크기까지 늘어난다. 예전에는 최대 높이 200 으로
    // 둬서 내용(약 90)보다 훨씬 큰 빈 회색 칸이 생겼다 — 상품 카드와 같은 높이로 고정한다.
    return SizedBox(
      height: ListCardMetrics.height,
      child: Material(
        color: NativeAdCard.background,
        elevation: ListCardMetrics.elevation,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(ListCardMetrics.radius),
        clipBehavior: Clip.antiAlias,
        child: AdWidget(ad: ad),
      ),
    );
  }
}
