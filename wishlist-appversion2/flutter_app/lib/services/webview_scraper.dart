import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'product_extract_js.dart';
import 'webview_extract_host.dart';

/// WebView 추출이 확정 가격을 못 냈을 때 남기는 실패 이유.
class ExtractFailureReason {
  static const loadingTimeout = 'loading_timeout';
  static const scriptTimeout = 'script_timeout';
  static const accessBlocked = 'access_blocked';
  static const networkError = 'network_error';
  static const notProductPage = 'not_product_page';
  static const priceAmbiguous = 'price_ambiguous';
  static const unsupportedCurrency = 'unsupported_currency';
}

/// 폴링·안정화 대기에서 실제 시각을 주입하기 위한 시계.
abstract class ExtractClock {
  DateTime now();
  Future<void> delay(Duration duration);
}

class SystemExtractClock implements ExtractClock {
  const SystemExtractClock();

  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

/// 단말에서 안 보이는 WebView 로 뽑아낸 상품정보 (Tier 2.5 결과).
class OnDeviceExtract {
  OnDeviceExtract({
    this.name,
    this.price,
    this.originalPrice,
    this.brand,
    this.image,
    this.siteName,
    this.hasJsonLd = false,
    this.looksLikeProductPage = false,
    this.blocked = false,
    this.finalUrl,
    this.source = const {},
    this.purchasePriceStatus = 'unknown',
    this.priceConfidence = 'unknown',
    this.availability = 'unknown',
    this.optionDependent,
    this.optionPriceMin,
    this.optionPriceMax,
    this.priceEvidence = const [],
    this.failureReason,
  });

  final String? name;
  final int? price;
  final int? originalPrice;
  final String? brand;
  final String? image;
  final String? siteName;
  final bool hasJsonLd;
  final bool looksLikeProductPage;
  final bool blocked;
  final String? finalUrl;
  final Map<String, dynamic> source;
  final String purchasePriceStatus;
  final String priceConfidence;
  final String availability;
  final bool? optionDependent;
  final int? optionPriceMin;
  final int? optionPriceMax;
  final List<Map<String, dynamic>> priceEvidence;
  final String? failureReason;

  bool get hasAnything => name != null || price != null || image != null;

  bool get isSoldOut {
    final value = availability.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return value == 'soldout' || value == 'outofstock';
  }

  OnDeviceExtract withFailureReason(String? reason) {
    if (failureReason == reason) return this;
    return OnDeviceExtract(
      name: name,
      price: price,
      originalPrice: originalPrice,
      brand: brand,
      image: image,
      siteName: siteName,
      hasJsonLd: hasJsonLd,
      looksLikeProductPage: looksLikeProductPage,
      blocked: blocked,
      finalUrl: finalUrl,
      source: source,
      purchasePriceStatus: purchasePriceStatus,
      priceConfidence: priceConfidence,
      availability: availability,
      optionDependent: optionDependent,
      optionPriceMin: optionPriceMin,
      optionPriceMax: optionPriceMax,
      priceEvidence: priceEvidence,
      failureReason: reason,
    );
  }

  static OnDeviceExtract? fromRaw(dynamic raw) {
    if (raw == null) return null;
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      return OnDeviceExtract(
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? (map['name'] as String).trim()
            : null,
        price: (map['price'] as num?)?.toInt(),
        originalPrice: (map['originalPrice'] as num?)?.toInt(),
        brand: map['brand'] as String?,
        image: map['image'] as String?,
        siteName: map['siteName'] as String?,
        hasJsonLd: map['hasJsonLd'] == true,
        looksLikeProductPage: map['looksLikeProductPage'] == true,
        blocked: map['blocked'] == true,
        finalUrl: map['finalUrl'] as String?,
        source: (map['source'] as Map?)?.cast<String, dynamic>() ?? const {},
        purchasePriceStatus: map['purchasePriceStatus'] as String? ?? 'unknown',
        priceConfidence: map['priceConfidence'] as String? ?? 'unknown',
        availability: map['availability'] as String? ?? 'unknown',
        optionDependent: map['optionDependent'] as bool?,
        optionPriceMin: (map['optionPriceMin'] as num?)?.toInt(),
        optionPriceMax: (map['optionPriceMax'] as num?)?.toInt(),
        priceEvidence:
            (map['priceEvidence'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            const [],
        failureReason: map['failureReason'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 리다이렉트/SPA 안정화, 스크립트 timeout, 차단 조기 종료, 빈 결과 1회 재시도를
/// WebView 구현과 분리해 단위 테스트할 수 있게 한 추출 루프.
class WebViewExtractLoop {
  WebViewExtractLoop({
    ExtractClock? clock,
    this.settleWindow = const Duration(milliseconds: 600),
    this.scriptTimeout = const Duration(seconds: 8),
    this.pollInterval = const Duration(milliseconds: 200),
    this.firstLoadTimeout = const Duration(seconds: 15),
  }) : clock = clock ?? const SystemExtractClock();

  final ExtractClock clock;
  final Duration settleWindow;
  final Duration scriptTimeout;
  final Duration pollInterval;
  final Duration firstLoadTimeout;

  DateTime? lastNavigationAt;
  bool loading = false;
  bool sawFirstLoad = false;
  bool loadWaitTimedOut = false;
  bool sawNetworkError = false;
  bool scriptTimedOut = false;
  int evaluateCount = 0;
  int reloadCount = 0;

  bool get isSettled {
    if (loading || lastNavigationAt == null) return false;
    return !clock.now().difference(lastNavigationAt!).isNegative &&
        clock.now().difference(lastNavigationAt!) >= settleWindow;
  }

  void onLoadStart(String? url) {
    if (isAboutBlankUrl(url)) return;
    loading = true;
    lastNavigationAt = clock.now();
  }

  void onLoadStop(String? url) {
    if (isAboutBlankUrl(url)) return;
    loading = false;
    sawFirstLoad = true;
    lastNavigationAt = clock.now();
  }

  void onHistoryUpdate(String? url) {
    if (isAboutBlankUrl(url)) return;
    // pushState만 반복하는 SPA(에이블리 등)가 settle을 영원히 미루지 않게,
    // 실제 문서 로딩 중일 때만 안정화 타이머를 갱신한다.
    if (loading) {
      lastNavigationAt = clock.now();
    }
  }

  void onNetworkError() {
    sawNetworkError = true;
    loading = false;
    sawFirstLoad = true;
    lastNavigationAt = clock.now();
  }

  Future<OnDeviceExtract?> run({
    required String requestUrl,
    required Future<dynamic> Function(String source) evaluate,
    required Future<void> Function(String url) loadUrl,
    required Duration maxWait,
    String extractSource = productExtractJs,
    bool Function()? isAlive,
  }) async {
    final loadDeadline = clock.now().add(firstLoadTimeout);
    while (!sawFirstLoad && clock.now().isBefore(loadDeadline)) {
      await clock.delay(pollInterval);
    }
    if (!sawFirstLoad) {
      // Headless WebView가 onLoadStop을 안 주는 경우가 있어, 컨트롤러가 있으면
      // 바로 포기하지 않고 추출을 한 번 시도한다.
      loadWaitTimedOut = true;
      loading = false;
      lastNavigationAt ??= clock.now();
    }

    final deadline = clock.now().add(maxWait);
    OnDeviceExtract? best;
    OnDeviceExtract? lastParsed;
    String? lastFingerprint;
    var emptyReloaded = false;

    while (clock.now().isBefore(deadline)) {
      if (isAlive != null && !isAlive()) {
        return _finish(best ?? lastParsed, requestUrl);
      }
      if (!isSettled) {
        final wait = _remaining(deadline);
        if (wait == null) break;
        await clock.delay(wait < pollInterval ? wait : pollInterval);
        continue;
      }

      var parsed = await _evaluateOnce(evaluate, extractSource);
      if (scriptTimedOut) {
        return _finish(best ?? lastParsed, requestUrl);
      }
      if (parsed != null &&
          isForeignExtractResult(requestUrl, parsed.finalUrl)) {
        parsed = null;
      }
      if (parsed != null) lastParsed = parsed;

      if (parsed != null && parsed.blocked) {
        return parsed.withFailureReason(ExtractFailureReason.accessBlocked);
      }

      if (_isEmpty(parsed)) {
        if (!emptyReloaded &&
            best == null &&
            !_isNonRetryable(parsed, requestUrl)) {
          emptyReloaded = true;
          reloadCount += 1;
          await loadUrl(requestUrl);
          continue;
        }
      } else if (parsed != null) {
        best = _prefer(best, parsed);
        final fingerprint = priceFingerprint(parsed);
        if (fingerprint != null) {
          if (fingerprint == lastFingerprint) {
            return parsed;
          }
          lastFingerprint = fingerprint;
        }
      }

      final wait = _remaining(deadline);
      if (wait == null) break;
      await clock.delay(wait < pollInterval ? wait : pollInterval);
    }

    return _finish(best ?? lastParsed, requestUrl);
  }

  Future<OnDeviceExtract?> _evaluateOnce(
    Future<dynamic> Function(String source) evaluate,
    String extractSource,
  ) async {
    evaluateCount += 1;
    try {
      final raw = await evaluate(extractSource).timeout(scriptTimeout);
      return OnDeviceExtract.fromRaw(raw);
    } on TimeoutException {
      scriptTimedOut = true;
      return null;
    }
  }

  Duration? _remaining(DateTime deadline) {
    final left = deadline.difference(clock.now());
    if (left <= Duration.zero) return null;
    return left;
  }

  OnDeviceExtract? _finish(OnDeviceExtract? best, String requestUrl) {
    if (best != null && (best.price != null || best.optionPriceMin != null)) {
      return best;
    }
    final reason = _classify(best, requestUrl);
    if (best != null) return best.withFailureReason(reason);
    return OnDeviceExtract(failureReason: reason);
  }

  String _classify(OnDeviceExtract? best, String requestUrl) {
    if (scriptTimedOut) return ExtractFailureReason.scriptTimeout;
    if (best?.blocked == true) return ExtractFailureReason.accessBlocked;
    final hostUrl = best?.finalUrl ?? requestUrl;
    if (best == null) {
      if (sawNetworkError) return ExtractFailureReason.networkError;
      if (loadWaitTimedOut && !sawFirstLoad) {
        return ExtractFailureReason.loadingTimeout;
      }
      if (evaluateCount > 0) return ExtractFailureReason.notProductPage;
      return ExtractFailureReason.loadingTimeout;
    }
    if (!best.looksLikeProductPage) {
      return ExtractFailureReason.notProductPage;
    }
    if (best.price == null) {
      if (isUnsupportedCurrencyHost(hostUrl)) {
        return ExtractFailureReason.unsupportedCurrency;
      }
      return ExtractFailureReason.priceAmbiguous;
    }
    return ExtractFailureReason.loadingTimeout;
  }
}

bool _isEmpty(OnDeviceExtract? parsed) =>
    parsed == null || (!parsed.hasAnything && !parsed.blocked);

bool _isNonRetryable(OnDeviceExtract? parsed, String requestUrl) {
  if (parsed == null) return false;
  if (parsed.blocked || parsed.isSoldOut) return true;
  if (parsed.looksLikeProductPage &&
      parsed.hasAnything &&
      parsed.price == null) {
    return true;
  }
  if (isUnsupportedCurrencyHost(parsed.finalUrl ?? requestUrl) &&
      parsed.price == null) {
    return true;
  }
  return false;
}

OnDeviceExtract _prefer(OnDeviceExtract? current, OnDeviceExtract next) {
  if (current == null) return next;
  return _quality(next) >= _quality(current) ? next : current;
}

int _quality(OnDeviceExtract value) {
  if (value.blocked) return -1;
  var score = 0;
  if (value.price != null) score += 100;
  if (value.optionPriceMin != null) score += 20;
  if (value.name != null) score += 10;
  if (value.image != null) score += 10;
  if (value.looksLikeProductPage) score += 5;
  switch (value.purchasePriceStatus) {
    case 'confirmed':
      score += 4;
    case 'option_dependent':
      score += 3;
    case 'provisional':
      score += 1;
  }
  switch (value.priceConfidence) {
    case 'high':
      score += 3;
    case 'medium':
      score += 2;
    case 'low':
      score += 1;
  }
  return score;
}

String? priceFingerprint(OnDeviceExtract value) {
  if (value.price == null && value.optionPriceMin == null) return null;
  return [
    value.finalUrl ?? '',
    value.source['adapter'] ?? '',
    value.price?.toString() ?? '',
    value.originalPrice?.toString() ?? '',
    value.optionPriceMin?.toString() ?? '',
    value.optionPriceMax?.toString() ?? '',
  ].join('|');
}

bool isUnsupportedCurrencyHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  return host == 'gap.com' ||
      host.endsWith('.gap.com') ||
      host == 'nugu.jp' ||
      host.endsWith('.nugu.jp');
}

bool isAboutBlankUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final value = url.trim().toLowerCase();
  return value == 'about:blank' || value.startsWith('about:blank?');
}

String? extractHost(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  return host;
}

/// `m.a-bly.com` / `mobile.a-bly.com`처럼 같은 등록 도메인의 형제 서브도메인을
/// 동일 사이트로 본다. `co.kr` 등 2단 TLD는 마지막 3라벨을 쓴다.
String? registrableDomain(String? host) {
  if (host == null || host.isEmpty) return null;
  final parts = host.toLowerCase().split('.');
  if (parts.length < 2) return host.toLowerCase();
  const multi = {'co', 'or', 'ne', 'ac', 'go', 'com', 'net', 'org'};
  if (parts.length >= 3 && multi.contains(parts[parts.length - 2])) {
    return parts.sublist(parts.length - 3).join('.');
  }
  return parts.sublist(parts.length - 2).join('.');
}

bool isSameExtractSite(String requestUrl, String? candidateUrl) {
  if (candidateUrl == null || candidateUrl.isEmpty) return false;
  if (isAboutBlankUrl(candidateUrl)) return false;
  final requestHost = extractHost(requestUrl);
  final candidateHost = extractHost(candidateUrl);
  if (requestHost == null || candidateHost == null) return false;
  if (requestHost == candidateHost) return true;
  if (requestHost.endsWith('.$candidateHost') ||
      candidateHost.endsWith('.$requestHost')) {
    return true;
  }
  final requestRoot = registrableDomain(requestHost);
  final candidateRoot = registrableDomain(candidateHost);
  return requestRoot != null &&
      candidateRoot != null &&
      requestRoot == candidateRoot;
}

bool isForeignExtractResult(String requestUrl, String? finalUrl) {
  if (finalUrl == null || finalUrl.isEmpty) return false;
  if (isAboutBlankUrl(finalUrl)) return true;
  return !isSameExtractSite(requestUrl, finalUrl);
}

/// Tier 2.5 — 안 보이는 WebView 로 렌더링된 페이지에서 상품정보를 추출한다.
///
/// 서버 엔진(Tier 1 API / Tier 2 HTTP GET)이 가격을 못 얻었을 때만 부른다.
/// 사용자 단말·사용자 세션으로 자기가 저장하려는 상품 페이지 1건을 여는 것이라
/// 서버측 크롤링보다 차단·약관 리스크가 훨씬 낮다.
///
/// WebView 가 있는 플랫폼(Android/iOS)에서만 동작한다. 그 외(웹·데스크톱)에서는
/// [isSupported] 가 false 이며 [extract] 는 null 을 반환해 기존 흐름을 유지한다.
class WebViewScraper {
  WebViewScraper({ExtractClock? clock})
    : _clock = clock ?? const SystemExtractClock();

  static const String _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 모바일 상품 URL(m.a-bly.com 등)은 데스크톱 UA면 로드가 안 끝나거나 빈 페이지가 된다.
  static const String mobileUa =
      'Mozilla/5.0 (Linux; Android 13; SM-T870) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static const String desktopUa = _desktopUa;

  static final InAppWebViewSettings extractSettings = InAppWebViewSettings(
    userAgent: _desktopUa,
    javaScriptEnabled: true,
    clearCache: false,
    mediaPlaybackRequiresUserGesture: true,
    transparentBackground: true,
    useHybridComposition: true,
  );

  final ExtractClock _clock;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// [url] 페이지를 열어 상품정보를 추출한다. 실패하면 실패 이유가 있는 결과 또는 null.
  Future<OnDeviceExtract?> extract(
    String url, {
    Duration maxWait = const Duration(seconds: 12),
  }) async {
    if (!isSupported) return null;

    final requestHost = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final effectiveMaxWait = requestHost.endsWith('anderssonbell.com')
        ? const Duration(seconds: 20)
        : (requestHost == 'a-bly.com' || requestHost.endsWith('.a-bly.com')
            ? const Duration(seconds: 28)
            : (requestHost == '4910.kr' || requestHost.endsWith('.4910.kr')
                ? const Duration(seconds: 20)
                : maxWait));

    final host = WebViewExtractHost.maybeInstance;
    if (host != null) {
      return host.extract(url,
          maxWait: effectiveMaxWait, clock: _clock);
    }

    InAppWebViewController? controller;
    HeadlessInAppWebView? headless;
    final firstLoadTimeout = requestHost == 'a-bly.com' ||
            requestHost.endsWith('.a-bly.com')
        ? const Duration(seconds: 40)
        : const Duration(seconds: 15);
    final loop = WebViewExtractLoop(
      clock: _clock,
      firstLoadTimeout: firstLoadTimeout,
    );

    try {
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSize: const Size(360, 640),
        initialSettings: extractSettings,
        onWebViewCreated: (c) {
          controller = c;
        },
        onLoadStart: (c, uri) {
          controller = c;
          loop.onLoadStart(uri?.toString());
        },
        onLoadStop: (c, uri) {
          controller = c;
          loop.onLoadStop(uri?.toString());
        },
        onUpdateVisitedHistory: (c, uri, _) {
          controller = c;
          loop.onHistoryUpdate(uri?.toString());
        },
        onReceivedError: (c, _, __) {
          controller = c;
          loop.onNetworkError();
        },
      );
      await headless.run();
      await headless.setSize(const Size(360, 640));
      controller ??= headless.webViewController;
      if (controller == null) {
        return OnDeviceExtract(
          failureReason: ExtractFailureReason.loadingTimeout,
        );
      }

      return loop.run(
        requestUrl: url,
        maxWait: effectiveMaxWait,
        isAlive: () => headless?.isRunning() == true,
        evaluate: (source) async {
          final view = headless;
          final current = view?.webViewController ?? controller;
          if (view == null || !view.isRunning() || current == null) {
            throw TimeoutException('webview not running');
          }
          return current.evaluateJavascript(source: source);
        },
        loadUrl: (target) async {
          final view = headless;
          final current = view?.webViewController ?? controller;
          if (view == null || !view.isRunning() || current == null) return;
          await current.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
        },
      );
    } catch (_) {
      return OnDeviceExtract(
        failureReason: loop.sawNetworkError
            ? ExtractFailureReason.networkError
            : ExtractFailureReason.loadingTimeout,
      );
    } finally {
      await headless?.dispose();
    }
  }
}
