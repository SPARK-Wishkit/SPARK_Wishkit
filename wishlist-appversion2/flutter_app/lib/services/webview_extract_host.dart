import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_scraper.dart';

/// 위젯 트리에 항상 붙어 있는 InAppWebView로 추출한다.
///
/// Headless는 Activity content 자식이 없으면 뷰 계층에 붙지 못한다.
/// 추출 순간에만 WebView를 만들면 `onWebViewCreated`가 15초 안에
/// 오지 않을 수 있어, about:blank로 미리 붙여 둔다.
class WebViewExtractHost extends StatefulWidget {
  const WebViewExtractHost({
    super.key,
    required this.child,
    this.mountWebView = true,
  });

  final Widget child;
  final bool mountWebView;

  static WebViewExtractHostState? get maybeInstance =>
      WebViewExtractHostState._instance;

  @override
  State<WebViewExtractHost> createState() => WebViewExtractHostState();
}

class WebViewExtractHostState extends State<WebViewExtractHost> {
  static WebViewExtractHostState? _instance;

  bool _busy = false;
  InAppWebViewController? _controller;
  WebViewExtractLoop? _loop;
  Completer<void>? _blankReady;
  String? _activeRequestUrl;
  bool _acceptAnyHostLoad = false;
  final Completer<InAppWebViewController> _created =
      Completer<InAppWebViewController>();

  bool get isReady => _controller != null;

  /// 컨트롤러가 붙은 뒤 단순 JS가 도는지 확인한다.
  Future<Object?> probeJavascript([String source = '1+1']) async {
    final controller = await _created.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('webview not created'),
    );
    return controller.evaluateJavascript(source: source).timeout(
      const Duration(seconds: 4),
    );
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
  }

  @override
  void dispose() {
    if (_instance == this) _instance = null;
    super.dispose();
  }

  Future<OnDeviceExtract?> extract(
    String url, {
    required Duration maxWait,
    required ExtractClock clock,
  }) async {
    if (_busy) {
      return OnDeviceExtract(
        failureReason: ExtractFailureReason.loadingTimeout,
      );
    }
    _busy = true;
    final requestHost = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final isAbly = requestHost == 'a-bly.com' ||
        requestHost.endsWith('.a-bly.com');
    final firstLoadTimeout = isAbly
        ? const Duration(seconds: 40)
        : const Duration(seconds: 15);
    final loop = WebViewExtractLoop(
      clock: clock,
      firstLoadTimeout: firstLoadTimeout,
    );

    try {
      final controller = await _created.future.timeout(
        loop.firstLoadTimeout,
        onTimeout: () => throw TimeoutException('webview not created'),
      );
      // 이전 상품 페이지의 load 콜백·DOM이 새 루프를 오염시키지 않게
      // about:blank onLoadStop까지 기다린 뒤에만 대상 URL을 연다.
      _loop = null;
      _activeRequestUrl = null;
      _acceptAnyHostLoad = false;
      await _resetToBlank(controller);
      _activeRequestUrl = url;
      // 에이블리는 봇 챌린지/중간 호스트로 리다이렉트되며 same-site 필터에
      // 막히면 onLoadStop이 루프에 안 들어온다.
      _acceptAnyHostLoad = isAbly;
      _loop = loop;
      try {
        await controller.setSettings(
          settings: InAppWebViewSettings(
            userAgent:
                isAbly ? WebViewScraper.mobileUa : WebViewScraper.desktopUa,
          ),
        );
      } catch (_) {}
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      return loop.run(
        requestUrl: url,
        maxWait: maxWait,
        isAlive: () => mounted && _controller != null,
        evaluate: (source) => controller.evaluateJavascript(source: source),
        loadUrl: (target) =>
            controller.loadUrl(urlRequest: URLRequest(url: WebUri(target))),
      );
    } on TimeoutException {
      return OnDeviceExtract(
        failureReason: ExtractFailureReason.loadingTimeout,
      );
    } catch (_) {
      return OnDeviceExtract(
        failureReason: loop.sawNetworkError
            ? ExtractFailureReason.networkError
            : ExtractFailureReason.loadingTimeout,
      );
    } finally {
      _loop = null;
      _activeRequestUrl = null;
      _acceptAnyHostLoad = false;
      _busy = false;
    }
  }

  bool get _isResetting => _blankReady != null;

  void _finishBlankReset() {
    final pending = _blankReady;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  Future<void> _resetToBlank(InAppWebViewController controller) async {
    _blankReady = Completer<void>();
    try {
      try {
        await controller.stopLoading();
      } catch (_) {}
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri('about:blank')),
        );
      } catch (_) {
        return;
      }
      try {
        await _blankReady!.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // blank 콜백이 안 와도 대상 URL 로드는 진행한다.
      }
    } finally {
      _finishBlankReset();
      _blankReady = null;
    }
  }

  bool _shouldForward(String? url) {
    if (_isResetting) return false;
    if (isAboutBlankUrl(url)) return false;
    final active = _activeRequestUrl;
    if (active == null) return false;
    if (_acceptAnyHostLoad) return true;
    if (url == null || url.isEmpty) return true;
    return isSameExtractSite(active, url);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.mountWebView && WebViewScraper.isSupported)
          Positioned(
            left: 0,
            top: 0,
            width: 360,
            height: 640,
            child: IgnorePointer(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri('about:blank')),
                initialSettings: WebViewScraper.extractSettings,
                onWebViewCreated: (controller) {
                  _controller = controller;
                  if (!_created.isCompleted) _created.complete(controller);
                },
                onLoadStart: (controller, uri) {
                  _controller = controller;
                  final url = uri?.toString();
                  if (_isResetting || !_shouldForward(url)) return;
                  _loop?.onLoadStart(url);
                },
                onLoadStop: (controller, uri) {
                  _controller = controller;
                  final url = uri?.toString();
                  if (_isResetting) {
                    if (isAboutBlankUrl(url)) _finishBlankReset();
                    return;
                  }
                  if (!_shouldForward(url)) return;
                  _loop?.onLoadStop(url);
                },
                onUpdateVisitedHistory: (controller, uri, _) {
                  _controller = controller;
                  final url = uri?.toString();
                  if (_isResetting || !_shouldForward(url)) return;
                  _loop?.onHistoryUpdate(url);
                },
                onReceivedError: (controller, _, __) {
                  _controller = controller;
                  if (_isResetting) {
                    _finishBlankReset();
                    return;
                  }
                  _loop?.onNetworkError();
                },
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}
