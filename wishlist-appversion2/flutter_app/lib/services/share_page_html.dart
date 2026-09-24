import '../models/models.dart';
import '../widgets/diary_widgets.dart';

/// Public HTML snapshots live this long, then Cloud Functions delete them.
const kSharePageTtl = Duration(days: 28);

String htmlEscape(String raw) {
  return raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String? safeHttpUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri.toString();
}

String formatShareExpiry(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  return '${local.year}년 ${local.month}월 ${local.day}일';
}

/// Standalone HTML that mirrors [SharedWishlistScreen] for link shares.
String buildSharePageHtml({
  required SharedBasket basket,
  required DateTime expiresAt,
}) {
  final title = htmlEscape(
    basket.title.trim().isEmpty ? '살까말까 공유' : basket.title.trim(),
  );
  final owner = htmlEscape(
    basket.ownerName.trim().isEmpty ? '친구' : basket.ownerName.trim(),
  );
  final expiryLabel = htmlEscape(formatShareExpiry(expiresAt));
  final firstImage = basket.items
      .map((p) => safeHttpUrl(p.image))
      .whereType<String>()
      .firstOrNull;
  final ogImage = firstImage == null ? '' : htmlEscape(firstImage);
  final description = htmlEscape(
    '$owner 님이 살까말까 바구니에서 상품 ${basket.items.length}개를 공유했어요',
  );

  final cards = basket.items.map(_productCardHtml).join('\n');
  final body = cards.isEmpty
      ? '<p class="empty">아직 공개된 아이템이 없어요</p>'
      : cards;

  return '''<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <meta name="description" content="$description">
  <meta property="og:title" content="$title">
  <meta property="og:description" content="$description">
  ${ogImage.isEmpty ? '' : '<meta property="og:image" content="$ogImage">'}
  <meta property="og:type" content="website">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Jua&family=Noto+Sans+KR:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --canvas: #ececea;
      --paper: #f7f4ee;
      --grid: rgba(217, 210, 198, 0.45);
      --white: #ffffff;
      --ink: #2f2a26;
      --muted: #8b7e74;
      --sand: #d5baa5;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--canvas);
      color: var(--ink);
      font-family: "Noto Sans KR", sans-serif;
    }
    header {
      background: var(--white);
      padding: 16px 20px 12px;
    }
    .brand {
      font-family: Jua, sans-serif;
      font-size: 13px;
      color: var(--muted);
      letter-spacing: 0.04em;
    }
    h1 {
      margin: 4px 0 0;
      font-family: Jua, sans-serif;
      font-size: 22px;
      font-weight: 500;
    }
    .subtitle {
      margin: 8px 20px 0;
      font-family: Jua, sans-serif;
      font-size: 13px;
      color: var(--muted);
    }
    .folder {
      margin: 12px 12px 24px;
      background: var(--sand);
      border: 3px solid var(--sand);
      border-radius: 18px 18px 0 0;
      min-height: 70vh;
    }
    .paper {
      background-color: var(--paper);
      background-image:
        linear-gradient(to right, var(--grid) 1px, transparent 1px),
        linear-gradient(to bottom, var(--grid) 1px, transparent 1px);
      background-size: 18px 18px;
      border-radius: 15px 15px 0 0;
      padding: 12px 12px 28px;
      min-height: 70vh;
    }
    .card {
      display: flex;
      gap: 12px;
      align-items: flex-start;
      background: var(--white);
      border-radius: 14px;
      padding: 10px;
      margin-bottom: 10px;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
      color: inherit;
      text-decoration: none;
    }
    .thumb {
      width: 72px;
      height: 72px;
      border-radius: 10px;
      object-fit: cover;
      background: var(--paper);
      flex: 0 0 72px;
    }
    .platform {
      font-size: 11px;
      color: var(--muted);
    }
    .name {
      margin-top: 2px;
      font-size: 14px;
      font-weight: 700;
      line-height: 1.35;
    }
    .price-row { margin-top: 6px; }
    .original {
      font-size: 11px;
      color: var(--muted);
      text-decoration: line-through;
      margin-right: 6px;
    }
    .price {
      font-size: 13px;
      font-weight: 700;
    }
    .empty {
      text-align: center;
      color: var(--muted);
      font-family: Jua, sans-serif;
      padding: 48px 12px;
    }
    footer {
      text-align: center;
      color: var(--muted);
      font-size: 12px;
      padding: 0 20px 32px;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <header>
    <div class="brand">wishkit</div>
    <h1>$title</h1>
  </header>
  <p class="subtitle">$owner 님이 공유한 살까말까 바구니</p>
  <div class="folder">
    <div class="paper">
      $body
    </div>
  </div>
  <footer>
    이 페이지는 $expiryLabel까지 볼 수 있어요. 그 뒤에는 자동으로 사라집니다.
  </footer>
</body>
</html>
''';
}

String _productCardHtml(Product product) {
  final platform = htmlEscape(product.platform);
  final name = htmlEscape(product.name);
  final price = htmlEscape(formatWon(product.price));
  final original = product.originalPrice == null
      ? ''
      : '<span class="original">${htmlEscape(formatWon(product.originalPrice!))}</span>';
  final imageUrl = safeHttpUrl(product.image);
  final image = imageUrl == null
      ? '<div class="thumb" aria-hidden="true"></div>'
      : '<img class="thumb" src="${htmlEscape(imageUrl)}" alt="">';
  final href = safeHttpUrl(product.productUrl);
  final inner = '''
      $image
      <div>
        <div class="platform">$platform</div>
        <div class="name">$name</div>
        <div class="price-row">$original<span class="price">$price</span></div>
      </div>''';
  if (href == null) {
    return '      <div class="card">$inner\n      </div>';
  }
  return '      <a class="card" href="${htmlEscape(href)}" target="_blank" rel="noopener noreferrer">$inner\n      </a>';
}
