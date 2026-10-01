"""
서버 렌더링 레이어.

`engine-ai-prototype/render.py`(2026-09-18 재현성 실측으로 유니클로 레이스 컨디션까지
고친 최종 버전)를 포팅했다. 렌더링 판단 로직(UA 선택, 차단 문구 패턴, 대기 종료 조건,
HTML 정제, MAX_CLEANED_CHARS, 스크린샷 캡처)은 전부 그대로다 — 바뀐 건 딱 하나,
**브라우저 생명주기**뿐이다.

원본은 매 호출(`render()`)마다 `sync_playwright()`로 새 브라우저 프로세스를 띄우고
끝나면 닫았다 — 로컬 배치 스크립트(bakeoff.py)에선 문제없지만, 서버 요구사항 4번
("브라우저 세션은 요청마다 새로 띄우지 말고 재사용")과 정면으로 어긋난다. 그래서
Playwright의 **async API**로 옮기고, 브라우저는 `main.py`의 FastAPI lifespan에서
한 번만 띄워서 앱 상태(`app.state.browser`)로 들고 있다가 `render()` 호출마다
새 **컨텍스트**(쿠키/세션이 요청 간에 안 섞이도록)만 새로 만들고 끝나면 컨텍스트만
닫는다 — 브라우저 프로세스 자체는 재사용된다.

sync → async로 바꾼 부분(`page.goto`, `page.evaluate`, `page.content`,
`page.screenshot` 등 전부 `await`가 붙음)을 빼면 로직은 원본과 동일하다. 이게
"이식 과정에서 실수로 정확도가 바뀌는" 위험을 줄이는 가장 안전한 방법이라고 판단했다.
"""
from __future__ import annotations

import asyncio
import re
import time
import urllib.parse
from dataclasses import dataclass

from bs4 import BeautifulSoup
from playwright.async_api import Browser
from playwright.async_api import TimeoutError as PWTimeoutError

DESKTOP_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)

# 모바일 UA가 필요한 몰 목록 (에이블리·무신사·지그재그 — webview_scraper.dart의
# needsMobileUa() 이식, engine-ai-prototype에서 그대로 가져옴).
MOBILE_UA_HOSTS = ("a-bly.com", "musinsa.com", "zigzag.kr", "onelink.me")
MOBILE_UA = (
    "Mozilla/5.0 (Linux; Android 13; SM-G991N) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
)

BLOCK_PATTERNS = re.compile(
    r"Access Denied|Powered and protected by Akamai|sec-if-cpt-container|"
    r"접근이?\s*제한|비정상적인\s*접근|일시적으로\s*차단|자동화된?\s*요청|"
    r"captcha|보안\s*확인|"
    # 에이블리에서 간헐적으로 걸리는 Cloudflare Turnstile 봇 체크("Just a moment...")
    # 탐지. 유니클로/KREAM류 접근 차단과 같은 부류라 우회는 안 하지만, 최소한 "차단됐다"는
    # 건 정확히 감지해서 결과를 신뢰하지 않도록 한다.
    r"Just a moment|cf-turnstile|challenges\.cloudflare\.com|cf_chl_opt",
    re.IGNORECASE,
)

MAX_CLEANED_CHARS = 130000  # AI 입력 토큰 비용 통제용 상한 (근거는 engine-ai-prototype 17절)


@dataclass
class RenderResult:
    url: str
    final_url: str
    ok: bool
    blocked: bool
    cleaned_html: str
    raw_text: str
    raw_html: str
    image_candidates: list
    elapsed_ms: int
    error: str | None = None
    screenshot: bytes = b""


def _pick_ua(url: str) -> str:
    host = urllib.parse.urlparse(url).netloc
    if any(h in host for h in MOBILE_UA_HOSTS):
        return MOBILE_UA
    return DESKTOP_UA


def _looks_blocked(html: str) -> bool:
    return bool(BLOCK_PATTERNS.search(html))


def _clean_html(html: str) -> tuple[str, str, list]:
    """스크립트/스타일 등을 제거하고, 텍스트+주요 속성만 남긴 '정제된 HTML'과 순수 텍스트,
    이미지 후보 목록을 반환한다. (engine-ai-prototype과 완전히 동일한 로직, 순수 Python이라
    async로 바꿀 이유가 없음)"""
    soup = BeautifulSoup(html, "html.parser")

    for tag in soup(["script", "style", "noscript", "svg", "iframe", "link", "meta"]):
        if tag.name == "script" and tag.get("type") == "application/ld+json":
            continue
        if tag.name == "meta" and tag.get("property", "").startswith(("og:", "product:")):
            continue
        tag.decompose()

    keep_attrs = {"id", "src", "href", "content", "property", "alt", "aria-label"}
    for tag in soup.find_all(True):
        attrs = dict(tag.attrs)
        for k in list(attrs.keys()):
            if k not in keep_attrs and not k.startswith("data-"):
                del tag.attrs[k]

    image_candidates = sorted(
        {img.get("src") for img in soup.find_all("img") if img.get("src")}
        | {m.get("content") for m in soup.find_all("meta", property="og:image") if m.get("content")}
    )

    cleaned_html = str(soup)
    if len(cleaned_html) > MAX_CLEANED_CHARS:
        cleaned_html = cleaned_html[:MAX_CLEANED_CHARS] + "\n<!-- truncated -->"

    raw_text = soup.get_text(separator=" ", strip=True)
    return cleaned_html, raw_text, image_candidates


async def render(
    browser: Browser, url: str, *, retry_on_block: bool = True, nav_timeout_ms: int = 20000
) -> RenderResult:
    """공유 브라우저(`browser`)에서 새 컨텍스트를 하나 열어 렌더링하고, 끝나면 그 컨텍스트만
    닫는다 — 브라우저 프로세스 자체는 호출자가 계속 들고 있다가 다음 요청에 재사용한다."""
    started = time.monotonic()
    ua = _pick_ua(url)
    parsed = urllib.parse.urlparse(url)
    home_url = f"{parsed.scheme}://{parsed.netloc}/"

    context = await browser.new_context(user_agent=ua, viewport={"width": 1280, "height": 1600})
    try:
        page = await context.new_page()

        async def load(target_url: str):
            await page.goto(target_url, timeout=nav_timeout_ms, wait_until="domcontentloaded")
            # 가격 텍스트가 실제로 보이는지를 최우선 신호로, ld+json/텍스트길이 같은 "약한
            # 신호"는 최소 3초 대기 후에만 인정한다 — 유니클로 레이스 컨디션 근본 수정
            # (design-doc-snapshot 21절)에서 확인된 정확한 조건.
            MIN_WAIT_BEFORE_WEAK_SIGNAL_S = 3.0
            for i in range(20):
                price_ready = await page.evaluate(
                    "() => /\\d{1,3}(,\\d{3})+\\s*원/.test(document.body.innerText)"
                )
                if price_ready:
                    break
                if i * 0.5 >= MIN_WAIT_BEFORE_WEAK_SIGNAL_S:
                    weak_ready = await page.evaluate(
                        "() => { const ld = document.querySelector('script[type=\"application/ld+json\"]');"
                        " return (!!ld && /\"(price|offers)\"/i.test(ld.textContent))"
                        " || document.body.innerText.length > 1500; }"
                    )
                    if weak_ready:
                        break
                await asyncio.sleep(0.5)

        await load(url)
        html = await page.content()

        if retry_on_block and _looks_blocked(html):
            # 홈 웜업 1회 재시도
            try:
                await page.goto(home_url, timeout=nav_timeout_ms, wait_until="domcontentloaded")
                await asyncio.sleep(1.0)
                await load(url)
                html = await page.content()
            except PWTimeoutError:
                pass

        blocked = _looks_blocked(html)
        final_url = page.url
        cleaned_html, raw_text, images = _clean_html(html)
        try:
            screenshot = await page.screenshot(type="jpeg", quality=70)
        except Exception:  # noqa: BLE001 — 스크린샷 실패는 텍스트 추출 흐름을 막지 않음
            screenshot = b""

        return RenderResult(
            url=url,
            final_url=final_url,
            ok=not blocked,
            blocked=blocked,
            cleaned_html=cleaned_html,
            raw_text=raw_text,
            raw_html=html,
            image_candidates=images,
            elapsed_ms=int((time.monotonic() - started) * 1000),
            screenshot=screenshot,
        )
    except Exception as exc:  # noqa: BLE001 — 렌더링 실패는 예외를 던지지 않고 결과로 표현
        return RenderResult(
            url=url,
            final_url="",
            ok=False,
            blocked=False,
            cleaned_html="",
            raw_text="",
            raw_html="",
            image_candidates=[],
            elapsed_ms=int((time.monotonic() - started) * 1000),
            error=f"{type(exc).__name__}: {exc}",
        )
    finally:
        await context.close()


async def launch_browser(playwright) -> Browser:
    """앱 시작 시 1회만 호출 — 이후 모든 요청이 이 브라우저 프로세스를 공유한다."""
    try:
        return await playwright.chromium.launch(channel="chrome", headless=True)
    except Exception:  # noqa: BLE001 — 크롬 채널이 없는 환경용 의도적 폴백
        return await playwright.chromium.launch(headless=True)
