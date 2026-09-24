/// Helpers for turning Android/iOS share payloads into a product share input.
///
/// Keep the complete text (not only the URL) so the product title that
/// shopping apps commonly put before a shortened URL can fill in when
/// WebView extraction does not return a name.
class ShareInput {
  ShareInput._();

  static final RegExp _httpUrl = RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  );

  static final RegExp _trailingSharePunctuation = RegExp(
    r'[\]\[(){}>,.;:!?]+$',
  );

  /// Returns the first valid HTTP(S) URL found anywhere in [text].
  static String? firstUrl(String? text) {
    if (text == null || text.trim().isEmpty) return null;

    for (final match in _httpUrl.allMatches(text)) {
      final candidate = match
          .group(0)!
          .replaceFirst(_trailingSharePunctuation, '');
      final uri = Uri.tryParse(candidate);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  /// Uses the share text around [url] as a product-name hint.
  static String? titleHint(String input, String? url) {
    var leftover = input;
    if (url != null && url.isNotEmpty) {
      leftover = leftover.replaceAll(url, ' ');
    }
    leftover = leftover.replaceAll(_httpUrl, ' ');
    leftover = leftover.replaceAll(RegExp(r'\s+'), ' ').trim();
    leftover = leftover.replaceAll(RegExp(r'^[\-–—:|]+|[\-–—:|]+$'), '').trim();
    if (leftover.length < 2 || leftover.length > 80) return null;
    return leftover;
  }

  /// Picks the first shared text containing a URL.
  ///
  /// The original text is returned so `상품명 + URL` can be used as a title
  /// hint when WebView extraction does not return a name. File paths and
  /// image-only shares are ignored.
  static String? fromCandidates(Iterable<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty && firstUrl(trimmed) != null) {
        return trimmed;
      }
    }
    return null;
  }
}
