/// WebView 추출 값과 실제 상품 페이지에서 확인한 이름·가격·사진을 비교한다.
///
/// 엔진 상품명에는 브랜드·옵션 같은 부가 정보가 붙을 수 있으므로
/// 완전 일치가 아니어도, 확인한 상품명이 엔진 이름에 포함되면 같은 상품으로 본다.
class LiveProductFields {
  const LiveProductFields({
    required this.name,
    required this.price,
    required this.image,
    this.brand,
  });

  final String name;
  final int price;
  final String image;
  final String? brand;
}

class LiveFieldCompareResult {
  const LiveFieldCompareResult({
    required this.nameMatch,
    required this.priceMatch,
    required this.imageMatch,
  });

  final bool nameMatch;
  final bool priceMatch;
  final bool imageMatch;

  bool get allMatch => nameMatch && priceMatch && imageMatch;
}

String normalizeProductName(String raw) {
  var text = raw.toLowerCase();
  text = text.replaceAll(RegExp(r'[\u2117\u00ae\u2122]'), '');
  text = text.replaceAll(RegExp(r'''['"`´‘’“”]'''), '');
  text = text.replaceAll(RegExp(r'[\[\](){}【】]'), ' ');
  text = text.replaceAll(RegExp(r'[_/,|·•~-]+'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

List<String> _nameTokens(String raw) {
  final normalized = normalizeProductName(raw);
  if (normalized.isEmpty) return const [];
  return normalized
      .split(' ')
      .where((token) => token.length >= 2)
      .toList(growable: false);
}

bool namesMatch({
  required String engineName,
  required String liveName,
  String? engineBrand,
}) {
  final engine = normalizeProductName(engineName);
  final live = normalizeProductName(liveName);
  if (engine.isEmpty || live.isEmpty) return false;
  if (engine == live) return true;
  if (engine.contains(live) || live.contains(engine)) return true;

  final brand = normalizeProductName(engineBrand ?? '');
  if (brand.isNotEmpty) {
    final engineWithoutBrand = engine.replaceAll(brand, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final liveWithoutBrand = live.replaceAll(brand, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (engineWithoutBrand.isNotEmpty &&
        liveWithoutBrand.isNotEmpty &&
        (engineWithoutBrand == liveWithoutBrand ||
            engineWithoutBrand.contains(liveWithoutBrand) ||
            liveWithoutBrand.contains(engineWithoutBrand))) {
      return true;
    }
    final brandedLive = '$brand $live'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (engine == brandedLive || engine.contains(brandedLive) || brandedLive.contains(engine)) {
      return true;
    }
  }

  final liveTokens = _nameTokens(liveName);
  final engineTokens = _nameTokens(engineName).toSet();
  if (liveTokens.length >= 2 &&
      liveTokens.every(engineTokens.contains)) {
    return true;
  }
  return false;
}

bool pricesMatch(int? enginePrice, int livePrice) {
  return enginePrice != null && enginePrice > 0 && enginePrice == livePrice;
}

String canonicalImageUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return raw.trim().toLowerCase();
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$path';
}

bool imagesMatch(String? engineImage, String liveImage) {
  if (engineImage == null || engineImage.isEmpty || liveImage.isEmpty) {
    return false;
  }
  final engine = canonicalImageUrl(engineImage);
  final live = canonicalImageUrl(liveImage);
  if (engine == live) return true;
  if (engine.contains(live) || live.contains(engine)) return true;

  String fileStem(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final file = path.split('/').last;
    return file.split('.').first.toLowerCase();
  }

  final engineStem = fileStem(engine);
  final liveStem = fileStem(live);
  if (engineStem.length < 6 || liveStem.length < 6) return false;
  return engineStem == liveStem ||
      engineStem.contains(liveStem) ||
      liveStem.contains(engineStem);
}

LiveFieldCompareResult compareLiveFields({
  required String? engineName,
  required int? enginePrice,
  required String? engineImage,
  required LiveProductFields live,
  String? engineBrand,
}) {
  return LiveFieldCompareResult(
    nameMatch: namesMatch(
      engineName: engineName ?? '',
      liveName: live.name,
      engineBrand: engineBrand ?? live.brand,
    ),
    priceMatch: pricesMatch(enginePrice, live.price),
    imageMatch: imagesMatch(engineImage, live.image),
  );
}
