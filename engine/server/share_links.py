"""
쇼핑몰 앱의 공유 링크(짧은 링크)를 실제 상품 페이지 주소로 바꾼다.

무신사 앱은 `https://musinsa.onelink.me/PvkC/…` 같은 AppsFlyer OneLink 를 공유한다. 이 주소는 "앱이 있나,
폰인가 PC인가"를 판단해서 앱·스토어·웹 중 하나로 다시 보내는 중간 페이지라, 서버 브라우저로 그대로 열면
앱/스토어로 보내려다 끝내 로딩이 안 끝난다(2026-10-24 로그: Page.goto Timeout 20000ms, onelink.me).

그래서 렌더링하기 전에 브라우저 없이 HTTP 요청만으로 리다이렉트를 따라가서 실제 주소를 얻는다.
- 일반 3xx 리다이렉트는 그대로 따라간다(PC 브라우저인 척해서 앱 대신 웹 주소로 보내지게 한다).
- `intent://`, `musinsa://` 처럼 앱으로 보내는 주소가 나오면, 그 주소나 직전 주소의 쿼리에 들어 있는
  웹 대체 주소(af_web_dp 등)를 꺼낸다.
- 어떤 이유로든 못 풀면 원래 주소를 그대로 돌려준다(렌더링 단계가 원래대로 시도한다).

표준 라이브러리만 쓴다(동기 함수 — main.py 에서 asyncio.to_thread 로 부른다).
"""
from __future__ import annotations

import logging
import re
import urllib.error
import urllib.parse
import urllib.request

logger = logging.getLogger("extract-server")

# 앱 공유용 짧은 링크·딥링크 서비스. 여기에 해당할 때만 미리 푼다(일반 상품 주소는 건드리지 않음).
SHORT_LINK_SUFFIXES = (
    "onelink.me",  # AppsFlyer (무신사 등)
    "app.link",  # Branch
    "page.link",  # Firebase Dynamic Links
    "naver.me",
    "link.coupang.com",
    "bit.ly",
    "han.gl",
    "url.kr",
)

# 앱으로 보내는 주소 안에 들어 있는 "웹으로 열 때 갈 주소" 파라미터 (앞에 있을수록 우선)
WEB_FALLBACK_PARAMS = ("af_web_dp", "$desktop_url", "$fallback_url", "af_r", "link", "url", "redirect", "deep_link_value")

DESKTOP_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
MAX_HOPS = 6
TOTAL_TIMEOUT_S = 4.0  # 엔진 전체 25초 안에서 렌더링·AI 에 시간을 남긴다


def _host(url: str) -> str:
    return (urllib.parse.urlsplit(url).hostname or "").lower()


def is_short_link(url: str) -> bool:
    host = _host(url)
    return any(host == s or host.endswith("." + s) for s in SHORT_LINK_SUFFIXES)


def _is_web(url: str) -> bool:
    return urllib.parse.urlsplit(url).scheme in ("http", "https") and bool(_host(url))


def web_fallback_in(url: str) -> str | None:
    """주소의 쿼리(와 intent:// 의 S.browser_fallback_url)에서 웹 대체 주소를 꺼낸다."""
    parts = urllib.parse.urlsplit(url)
    params = urllib.parse.parse_qs(parts.query)
    # Android intent://…#Intent;…;S.browser_fallback_url=https%3A…;end
    for piece in parts.fragment.split(";"):
        if piece.startswith("S.browser_fallback_url="):
            params.setdefault("browser_fallback_url", []).append(urllib.parse.unquote(piece.split("=", 1)[1]))
    for name in (*WEB_FALLBACK_PARAMS, "browser_fallback_url"):
        for value in params.get(name, []):
            candidate = urllib.parse.unquote(value) if "%3A" in value.upper() else value
            if _is_web(candidate) and not is_short_link(candidate):
                return candidate
    return None


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):  # 리다이렉트를 직접 따라간다(앱 주소를 가로채려고)
        return None


_opener = urllib.request.build_opener(_NoRedirect)
_URL_IN_TEXT = re.compile(r"https?://[^\s\"'<>\\]+", re.IGNORECASE)
_NOT_PRODUCT = re.compile(
    r"(appsflyer|onelink|apple\.com|play\.google|googleapis|gstatic|facebook|cdn|static)"
    r"|\.(js|css|png|jpe?g|gif|svg|webp|ico|woff2?)(\?|$)",
    re.IGNORECASE,
)


def _fetch(url: str, timeout: float) -> tuple[str | None, str]:
    """한 번 요청한다. (리다이렉트 목적지 또는 None, 최종 페이지면 본문 앞부분)."""
    req = urllib.request.Request(url, headers={"User-Agent": DESKTOP_UA, "Accept": "text/html"})
    try:
        with _opener.open(req, timeout=timeout) as resp:
            return None, resp.read(200_000).decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        if 300 <= exc.code < 400:
            location = exc.headers.get("Location")
            return (urllib.parse.urljoin(url, location) if location else None), ""
        raise


def _brand_of(short_url: str) -> str:
    """musinsa.onelink.me → 'musinsa'. 짧은 링크 서비스의 하위 도메인이 보통 쇼핑몰 이름이다."""
    host = _host(short_url)
    for suffix in ("onelink.me", "app.link", "page.link"):
        if host.endswith("." + suffix):
            return host[: -len(suffix) - 1].split(".")[-1]
    return ""


def web_url_in_page(html: str, short_url: str) -> str | None:
    """중간 페이지(JS 로 넘기는 페이지) 본문에서 쇼핑몰 웹 주소를 찾는다. 쇼핑몰 이름이 든 주소를 우선한다."""
    brand = _brand_of(short_url)
    candidates = []
    text = html.replace("\\/", "/").replace("&amp;", "&")  # JS 문자열의 https:\/\/… 를 되돌린다
    for raw in _URL_IN_TEXT.findall(text):
        url = urllib.parse.unquote(raw)
        if _is_web(url) and not is_short_link(url) and not _NOT_PRODUCT.search(url):
            candidates.append(url)
    if brand:
        branded = [u for u in candidates if brand in _host(u)]
        if branded:
            return branded[0]
    return None  # 쇼핑몰 이름으로 못 고르면 추측하지 않는다(엉뚱한 페이지를 읽지 않게)


def resolve_share_link(url: str, *, fetch=_fetch, total_timeout: float = TOTAL_TIMEOUT_S) -> str:
    """짧은 링크면 실제 상품 주소로, 아니면 그대로. 실패해도 예외 없이 원래 주소를 돌려준다."""
    if not is_short_link(url):
        return url
    current = url
    per_hop = max(0.5, total_timeout / 3)
    try:
        for _ in range(MAX_HOPS):
            nxt, body = fetch(current, per_hop)
            if nxt is None:
                # 최종 페이지. 아직 짧은 링크 쪽이면 JS 로 넘기는 중간 페이지라 본문에서 웹 주소를 찾는다.
                if is_short_link(current):
                    current = web_url_in_page(body, url) or web_fallback_in(current) or current
                break
            if not _is_web(nxt):
                # 앱/스토어로 보내는 주소 → 그 안이나 직전 주소에 적힌 웹 주소를 쓴다
                current = web_fallback_in(nxt) or web_fallback_in(current) or current
                break
            current = nxt
    except Exception as exc:  # noqa: BLE001 — 못 풀면 원래 주소로 렌더링을 시도한다
        logger.warning("공유 링크 풀기 실패(%s): %s", url, exc)
        return web_fallback_in(url) or url
    if current != url:
        logger.info("공유 링크 → 상품 주소: %s → %s", url, current)
    return current
