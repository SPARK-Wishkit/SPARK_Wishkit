"""share_links.py — 앱 공유용 짧은 링크를 실제 상품 주소로 풀기."""
import http.server
import threading

import pytest

import share_links
from share_links import (
    is_short_link,
    resolve_share_link,
    web_fallback_in,
    web_url_in_page,
)

SHORT = "https://musinsa.onelink.me/PvkC/cw1qxmxp"
PRODUCT = "https://www.musinsa.com/products/4341120"


def _fake(routes: dict):
    """주소 → (다음 주소 또는 None, 본문). 예외를 넣으면 그 예외를 던진다."""
    calls = []

    def fetch(url, timeout):
        calls.append(url)
        value = routes[url]
        if isinstance(value, Exception):
            raise value
        return value

    return fetch, calls


def test_ordinary_product_url_is_not_touched():
    fetch, calls = _fake({})
    assert resolve_share_link(PRODUCT, fetch=fetch) == PRODUCT
    assert calls == []


def test_follows_redirects_to_the_product_page():
    fetch, _ = _fake({
        SHORT: ("https://www.musinsa.com/app/goods/4341120", ""),
        "https://www.musinsa.com/app/goods/4341120": (PRODUCT, ""),
        PRODUCT: (None, "<html>상품</html>"),
    })
    assert resolve_share_link(SHORT, fetch=fetch) == PRODUCT


def test_app_redirect_uses_web_fallback_in_query():
    app_url = "musinsa://goods/4341120?af_web_dp=https%3A%2F%2Fwww.musinsa.com%2Fproducts%2F4341120"
    fetch, _ = _fake({SHORT: (app_url, "")})
    assert resolve_share_link(SHORT, fetch=fetch) == PRODUCT


def test_android_intent_browser_fallback():
    intent = ("intent://goods/4341120#Intent;scheme=musinsa;package=com.musinsa.store;"
              "S.browser_fallback_url=https%3A%2F%2Fwww.musinsa.com%2Fproducts%2F4341120;end")
    fetch, _ = _fake({SHORT: (intent, "")})
    assert resolve_share_link(SHORT, fetch=fetch) == PRODUCT


def test_javascript_landing_page_picks_the_shop_url():
    page = """<html><script src="https://cdn.appsflyer.com/sdk.js"></script>
    <script>var store="https://apps.apple.com/kr/app/id1003139529";
    window.location.replace("https:\\/\\/www.musinsa.com\\/products\\/4341120?utm_source=af");</script></html>"""
    fetch, _ = _fake({SHORT: (None, page)})
    assert resolve_share_link(SHORT, fetch=fetch) == PRODUCT + "?utm_source=af"


def test_landing_page_without_shop_url_keeps_original_instead_of_guessing():
    page = '<a href="https://www.example.com/other">x</a>'
    fetch, _ = _fake({SHORT: (None, page)})
    assert resolve_share_link(SHORT, fetch=fetch) == SHORT


def test_network_error_returns_original():
    fetch, _ = _fake({SHORT: TimeoutError("timed out")})
    assert resolve_share_link(SHORT, fetch=fetch) == SHORT


@pytest.mark.parametrize("url,expected", [
    (SHORT, True),
    ("https://naver.me/abc", True),
    ("https://link.coupang.com/a/b", True),
    (PRODUCT, False),
    ("https://notonelink.me.example.com/x", False),
])
def test_is_short_link(url, expected):
    assert is_short_link(url) is expected


def test_web_fallback_and_page_scan_helpers():
    assert web_fallback_in("https://x.onelink.me/a?af_web_dp=https%3A%2F%2Fwww.musinsa.com%2Fproducts%2F1") \
        == "https://www.musinsa.com/products/1"
    assert web_fallback_in("musinsa://goods/1") is None
    assert web_url_in_page('"https://www.musinsa.com/products/9"', SHORT) == "https://www.musinsa.com/products/9"


def test_real_http_redirect_chain(monkeypatch):
    """실제 HTTP(로컬 서버)로 302 → 302 → 200 을 따라가는지. 짧은 링크 호스트로 127.0.0.1 을 쓴다."""
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            port = self.server.server_address[1]
            if self.path == "/short":
                assert "Windows NT" in self.headers["User-Agent"]  # PC 브라우저인 척해야 웹 주소로 보내 준다
                self.send_response(302)
                self.send_header("Location", f"http://localhost:{port}/app/goods/7")
            elif self.path == "/app/goods/7":
                self.send_response(301)
                self.send_header("Location", "/products/7")
            else:
                self.send_response(200)
            self.end_headers()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    monkeypatch.setattr(share_links, "SHORT_LINK_SUFFIXES", ("127.0.0.1",))
    try:
        assert resolve_share_link(f"http://127.0.0.1:{port}/short") == f"http://localhost:{port}/products/7"
    finally:
        server.shutdown()
