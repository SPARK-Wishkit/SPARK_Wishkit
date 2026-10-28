/// Helpers for turning Android/iOS share payloads into a product share input.
///
/// Keep the complete text (not only the URL) so the product title that
/// shopping apps commonly put before a shortened URL can fill in when
/// server AI extraction does not return a name.
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
    final urls = _urls(text);
    return urls.isEmpty ? null : urls.first;
  }

  /// [text] 안의 HTTP(S) URL 들을 나온 순서대로, 중복 없이.
  static List<String> _urls(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final out = <String>[];
    for (final match in _httpUrl.allMatches(text)) {
      final candidate = _undoGluedRepeat(
        match.group(0)!.replaceFirst(_trailingSharePunctuation, ''),
      );
      final uri = Uri.tryParse(candidate);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          !out.contains(candidate)) {
        out.add(candidate);
      }
    }
    return out;
  }

  static final RegExp _scheme = RegExp('https?://', caseSensitive: false);
  static final RegExp _punctuationOnly = RegExp(r'^[\]\[(){}<>,.;:!?\-–—|·]+$');

  /// 같은 URL 이 띄어쓰기 없이 붙어 들어온 경우('https://a/1https://a/1') 하나로 줄인다.
  /// 정확히 같은 URL 의 반복일 때만 자른다 — `?redirect=https://…` 처럼 URL 안에 다른 URL 이
  /// 들어 있는 정상 주소는 건드리지 않는다.
  static String _undoGluedRepeat(String candidate) {
    final second = _scheme.allMatches(candidate).skip(1).firstOrNull;
    if (second == null) return candidate;
    final unit = candidate.substring(0, second.start);
    if (candidate.length % unit.length != 0) return candidate;
    return unit * (candidate.length ~/ unit.length) == candidate ? unit : candidate;
  }

  /// 공유로 받은 글을 정리한다: 같은 URL·같은 줄이 여러 번 들어오면 한 번씩만 남긴다.
  ///
  /// iOS 공유 시트는 한 번 공유에 같은 URL 을 공유 글·URL 첨부·텍스트 첨부로 여러 번 넘겨서,
  /// 그대로 두면 입력칸에 같은 주소가 3~4번 보이고 저장할 때 상품 URL 에 그대로 들어갈 수 있었다.
  /// 결과: URL 이 아닌 글 줄(상품명 등) → URL 들 순서, 줄바꿈으로 구분.
  static String normalize(String text) {
    final lines = <String>[];
    for (final raw in text.replaceAll(_httpUrl, '\n').split('\n')) {
      final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty || _punctuationOnly.hasMatch(line)) continue; // URL 을 뺀 자리에 남은 괄호·마침표
      if (!lines.contains(line)) lines.add(line);
    }
    return [...lines, ..._urls(text)].join('\n');
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
  /// hint when server AI extraction does not return a name. File paths and
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
