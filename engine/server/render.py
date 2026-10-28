"""
서버 렌더링 레이어.

`engine-ai-prototype/render.py`(유니클로 레이스 컨디션까지 고친 최종 버전)를 포팅했다. 렌더링
판단 로직(UA 선택, 차단 문구 패턴, 대기 종료 조건, HTML 정제, MAX_CLEANED_CHARS, 스크린샷)은
원본과 동일하고, 바뀐 건 브라우저 생명주기뿐이다.

원본은 호출마다 브라우저 프로세스를 새로 띄웠지만, 서버에서는 `launch_browser()`로 앱 시작 시
한 번만 띄우고(main.py lifespan) `render()` 호출마다 새 **컨텍스트**만 열고 닫는다 — 쿠키/세션은
요청 간에 섞이지 않고, 브라우저 프로세스는 재사용된다.
"""
from __future__ import annotations

import asyncio
import re
import urllib.parse
from dataclasses import dataclass, field

from bs4 import BeautifulSoup
from playwright.async_api import Browser
from playwright.async_api import TimeoutError as PWTimeoutError

DESKTOP_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)

# 모바일 UA가 필요한 몰 (에이블리·무신사·지그재그). 공유용 짧은 링크(onelink.me)는 뺐다 — 휴대폰인 척하면
# 앱/스토어로 보내려다 로딩이 안 끝난다. 짧은 링크는 렌더링 전에 share_links.py 가 실제 주소로 푼다.
MOBILE_UA_HOSTS = ("a-bly.com", "musinsa.com", "zigzag.kr")
MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; SM-G991N) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
)

BLOCK_PATTERNS = re.compile(
    r"Access Denied|Powered and protected by Akamai|sec-if-cpt-container|"
    r"접근이?\s*제한|비정상적인\s*접근|일시적으로\s*차단|자동화된?\s*요청|"
    r"captcha|보안\s*확인|"
    # 에이블리에서 간헐적으로 걸리는 Cloudflare Turnstile("Just a moment...") 탐지. 우회는 안
    # 하지만, 차단됐다는 건 정확히 감지해서 결과를 신뢰하지 않도록 한다.
    r"Just a moment|cf-turnstile|challenges\.cloudflare\.com|cf_chl_opt",
    re.IGNORECASE,
)

MAX_CLEANED_CHARS = 130000  # AI 입력 토큰 비용 통제용 상한 (근거: engine-ai-prototype 17절)

VIEWPORT = {"width": 1280, "height": 1600}

# 렌더링 완료 대기 조건 (design-doc-snapshot 21절, 유니클로 레이스 컨디션 근본 수정).
# 가격 텍스트가 실제로 보이면 즉시 종료(강한 신호). ld+json 가격/본문 길이 같은 약한 신호는
# 최소 3초가 지난 뒤에만 인정한다. 최대 20회 × 0.5초 = 10초.
POLL_INTERVAL_S = 0.5
POLL_MAX_ITERATIONS = 20
MIN_WAIT_BEFORE_WEAK_SIGNAL_S = 3.0
_JS_PRICE_VISIBLE = r"() => /\d{1,3}(,\d{3})+\s*원/.test(document.body.innerText)"
_JS_WEAK_READY = r"""() => {
  const ld = document.querySelector('script[type="application/ld+json"]');
  return (!!ld && /"(price|offers)"/i.test(ld.textContent)) || document.body.innerText.length > 1500;
}"""

_STRIP_TAGS = ["script", "style", "noscript", "svg", "iframe", "link", "meta"]
_KEEP_ATTRS = {"id", "src", "href", "content", "property", "alt", "aria-label"}


@dataclass
class RenderResult:
    final_url: str = ""
    blocked: bool = False
    cleaned_html: str = ""
    raw_text: str = ""
    image_candidates: list[str] = field(default_factory=list)
    screenshot: bytes = b""
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None and not self.blocked


def _pick_ua(host: str) -> str:
    return MOBILE_UA if any(h in host for h in MOBILE_UA_HOSTS) else DESKTOP_UA


def _looks_blocked(html: str) -> bool:
    return bool(BLOCK_PATTERNS.search(html))


def _clean_html(html: str) -> tuple[str, str, list[str]]:
    """스크립트/스타일 등을 제거하고 주요 속성만 남긴 '정제된 HTML', 순수 텍스트, 이미지 후보
    목록을 반환한다. ld+json 스크립트와 og:/product: 메타는 남긴다(가격·이미지 단서)."""
    soup = BeautifulSoup(html, "html.parser")

    for tag in soup(_STRIP_TAGS):
        if tag.name == "script" and tag.get("type") == "application/ld+json":
            continue
        if tag.name == "meta" and tag.get("property", "").startswith(("og:", "product:")):
            continue
        tag.decompose()

    for tag in soup.find_all(True):
        tag.attrs = {k: v for k, v in tag.attrs.items() if k in _KEEP_ATTRS or k.startswith("data-")}

    image_candidates = sorted(
        {img["src"] for img in soup.find_all("img") if img.get("src")}
        | {m["content"] for m in soup.find_all("meta", property="og:image") if m.get("content")}
    )

    cleaned_html = str(soup)
    if len(cleaned_html) > MAX_CLEANED_CHARS:
        cleaned_html = cleaned_html[:MAX_CLEANED_CHARS] + "\n<!-- truncated -->"

    return cleaned_html, soup.get_text(separator=" ", strip=True), image_candidates


async def _goto_and_wait(page, url: str, nav_timeout_ms: int) -> None:
    await page.goto(url, timeout=nav_timeout_ms, wait_until="domcontentloaded")
    for i in range(POLL_MAX_ITERATIONS):
        if await page.evaluate(_JS_PRICE_VISIBLE):
            return
        if i * POLL_INTERVAL_S >= MIN_WAIT_BEFORE_WEAK_SIGNAL_S and await page.evaluate(_JS_WEAK_READY):
            return
        await asyncio.sleep(POLL_INTERVAL_S)


async def render(browser: Browser, url: str, *, nav_timeout_ms: int = 20000) -> RenderResult:
    """공유 브라우저에서 새 컨텍스트를 열어 렌더링하고, 끝나면 그 컨텍스트만 닫는다.
    실패는 예외를 던지지 않고 `RenderResult.error`로 표현한다."""
    parsed = urllib.parse.urlparse(url)
    context = await browser.new_context(user_agent=_pick_ua(parsed.netloc), viewport=VIEWPORT)
    try:
        page = await context.new_page()
        await _goto_and_wait(page, url, nav_timeout_ms)
        html = await page.content()

        if _looks_blocked(html):
            # 홈 웜업 후 1회 재시도
            try:
                await page.goto(f"{parsed.scheme}://{parsed.netloc}/",
                                timeout=nav_timeout_ms, wait_until="domcontentloaded")
                await asyncio.sleep(1.0)
                await _goto_and_wait(page, url, nav_timeout_ms)
                html = await page.content()
            except PWTimeoutError:
                pass

        cleaned_html, raw_text, images = _clean_html(html)
        try:
            screenshot = await page.screenshot(type="jpeg", quality=70)
        except Exception:  # noqa: BLE001 — 스크린샷 실패는 텍스트 추출 흐름을 막지 않음
            screenshot = b""

        return RenderResult(
            final_url=page.url,
            blocked=_looks_blocked(html),
            cleaned_html=cleaned_html,
            raw_text=raw_text,
            image_candidates=images,
            screenshot=screenshot,
        )
    except Exception as exc:  # noqa: BLE001
        return RenderResult(error=f"{type(exc).__name__}: {exc}")
    finally:
        await context.close()


async def launch_browser(playwright) -> Browser:
    """앱 시작 시 1회만 호출 — 이후 모든 요청이 이 브라우저 프로세스를 공유한다.
    설치된 Chrome을 우선 쓰고, 없으면 Playwright 번들 Chromium으로 폴백한다."""
    try:
        return await playwright.chromium.launch(channel="chrome", headless=True)
    except Exception:  # noqa: BLE001
        return await playwright.chromium.launch(headless=True)
