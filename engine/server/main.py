"""
Wishkit 상품 추출 엔진 — AI 완전 의존 방식 서버.

engine-ai-prototype(2026-09-18 결정: 몰별 DOM 규칙 폐기, 서버 AI가 상품 페이지를 읽어 구조화
추출)에서 골든셋 36개로 검증한 파이프라인을 HTTP 서버로 감싼 것.

흐름: POST /extract {url} → 렌더링(공유 브라우저, 새 컨텍스트) → cleaned_html을 Gemini에 전달
→ ambiguous면 스크린샷으로 Gemini 비전 재시도 → 그라운딩 체크 → JSON 응답.

POST /identify-tag {image_base64, mime_type} → 태그 사진에서 품번을 읽고, 검색으로 찾은 상품
페이지에 그 품번이 실제로 있는지 확인해 URL을 돌려준다(가격은 읽지 않음 — tag_identify.py 참고).

실행: `uvicorn main:app --host 0.0.0.0 --port 8000` (.env에 GEMINI_API_KEY 필요 — .env.example 참고).
"""
from __future__ import annotations

import asyncio
import base64
import binascii
import logging
from contextlib import asynccontextmanager
from functools import partial
from typing import Literal

from fastapi import FastAPI, HTTPException
from playwright.async_api import async_playwright
from pydantic import BaseModel, HttpUrl

import config
from cache import CachedExtraction, NoOpCache, normalize_cache_key
from compare import grounding_check
from metrics import PeakRSSSampler, now_ms
from providers import ProviderResult, call_gemini, call_gemini_vision
from render import launch_browser, render
from share_links import resolve_share_link
from tag_identify import (
    IdentifyError,
    PageView,
    call_gemini_search,
    call_gemini_tag,
    identify,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("extract-server")

CACHE_TTL_S = 3600


class ExtractRequest(BaseModel):
    url: HttpUrl


class IdentifyTagRequest(BaseModel):
    image_base64: str
    mime_type: Literal["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"] = "image/jpeg"


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 브라우저는 요청마다 띄우지 않고 앱 생명주기 동안 재사용한다.
    async with async_playwright() as playwright:
        browser = await launch_browser(playwright)
        app.state.browser = browser
        app.state.gemini_semaphore = asyncio.Semaphore(config.GEMINI_MAX_CONCURRENCY)
        app.state.render_semaphore = asyncio.Semaphore(config.RENDER_MAX_CONCURRENCY)
        app.state.cache = NoOpCache()  # 실제 캐시 백엔드는 아직 미구현
        logger.info(
            "서버 시작 — 브라우저 준비 완료 (GEMINI_MAX_CONCURRENCY=%s, RENDER_MAX_CONCURRENCY=%s, EXTRACT_TIMEOUT_S=%s)",
            config.GEMINI_MAX_CONCURRENCY, config.RENDER_MAX_CONCURRENCY, config.EXTRACT_TIMEOUT_S,
        )
        try:
            yield
        finally:
            await browser.close()
            logger.info("서버 종료 — 브라우저 정리 완료")


app = FastAPI(title="wishkit-ai-extraction-engine", lifespan=lifespan)


async def _run_gemini(fn, *args) -> tuple[ProviderResult, int]:
    """동시 Gemini 호출 수를 세마포어로 제한하고, 동기 함수(내부 time.sleep 재시도)를
    스레드에서 돌린다. (결과, 소요 ms)를 반환한다."""
    started = now_ms()
    async with app.state.gemini_semaphore:
        result = await asyncio.to_thread(fn, *args)
    return result, now_ms() - started


async def _extract(url: str) -> dict:
    """렌더링 실패/차단/AI 호출 실패는 HTTPException(502)으로 올린다.
    ambiguous:true는 정상 결과이지 에러가 아니다."""
    t_start = now_ms()
    # 앱 공유용 짧은 링크(musinsa.onelink.me 등)는 실제 상품 주소로 먼저 바꾼다(share_links.py).
    url = await asyncio.to_thread(resolve_share_link, url)
    cache_key = normalize_cache_key(url)
    cached = await app.state.cache.get(cache_key)
    if cached is not None:
        return {**cached.data, "metrics": {**cached.data.get("metrics", {}), "cache_hit": True}}

    async with app.state.render_semaphore:
        r = await render(app.state.browser, url, nav_timeout_ms=config.RENDER_NAV_TIMEOUT_MS)
    render_elapsed_ms = now_ms() - t_start

    if r.error:
        raise HTTPException(502, f"렌더링 오류: {r.error}")
    if r.blocked:
        raise HTTPException(502, f"상품 페이지 접근이 차단됨(final_url={r.final_url})")

    text_result, text_elapsed_ms = await _run_gemini(call_gemini, r.cleaned_html)
    if not text_result.ok or not text_result.data:
        raise HTTPException(502, f"AI 호출 실패: {text_result.error}")
    extracted = text_result.data

    screenshot_fallback_used = False
    vision_elapsed_ms = 0
    if extracted.get("ambiguous") and r.screenshot:
        vision_result, vision_elapsed_ms = await _run_gemini(
            call_gemini_vision, r.screenshot, r.image_candidates
        )
        if vision_result.ok and vision_result.data:
            extracted = vision_result.data
            screenshot_fallback_used = True
        else:
            logger.warning("스크린샷 폴백 실패(%s) — 텍스트 결과를 그대로 사용", vision_result.error)

    response = {
        **extracted,
        "grounding": grounding_check(extracted, r.raw_text, r.image_candidates),
        "screenshot_fallback_used": screenshot_fallback_used,
        "render": {"ok": r.ok, "blocked": r.blocked, "final_url": r.final_url},
        "metrics": {
            "total_elapsed_ms": now_ms() - t_start,
            "render_elapsed_ms": render_elapsed_ms,
            "gemini_text_elapsed_ms": text_elapsed_ms,
            "gemini_vision_elapsed_ms": vision_elapsed_ms,
            "cache_hit": False,
        },
    }
    await app.state.cache.set(
        cache_key, CachedExtraction(data=response, cached_at_ms=now_ms()), ttl_seconds=CACHE_TTL_S
    )
    return response


@app.post("/extract")
async def extract(req: ExtractRequest):
    url = str(req.url)
    async with PeakRSSSampler(interval_ms=config.RSS_SAMPLE_INTERVAL_MS) as sampler:
        try:
            result = await asyncio.wait_for(_extract(url), timeout=config.EXTRACT_TIMEOUT_S)
        except TimeoutError:
            raise HTTPException(
                504, f"요청 처리 시간이 {config.EXTRACT_TIMEOUT_S}초를 넘어 취소됨: {url}"
            ) from None
        except HTTPException:
            raise
        except Exception as exc:
            logger.exception("알 수 없는 오류: %s", url)
            raise HTTPException(500, f"{type(exc).__name__}: {exc}") from exc

    result["metrics"]["peak_rss_mb"] = round(sampler.peak_rss_mb, 1)
    return result


# base64는 4바이트마다 원본 3바이트 — 디코딩하기 전에 길이만으로 너무 큰 요청을 먼저 거른다.
_MAX_IMAGE_BASE64_CHARS = -(-config.IDENTIFY_MAX_IMAGE_BYTES // 3) * 4


async def _render_for_identify(url: str, budget_s: float) -> PageView:
    """후보 페이지 하나 렌더링. 남은 시간(budget_s) 안에 못 끝내면 실패로 돌려서 전체 요청이
    504로 끝나지 않게 한다(앞에서 읽은 태그 정보는 not_found로라도 앱에 돌려주기 위해).

    렌더링 슬롯(render_semaphore)을 기다리는 시간도 budget_s 안에 넣는다 — /extract 요청이 몰려
    슬롯이 다 차 있으면 원래는 슬롯이 빌 때까지 무작정 기다리다가 전체 25초를 넘겨 504가 났다."""
    budget_s = max(1.0, budget_s)
    nav_timeout_ms = int(min(config.RENDER_NAV_TIMEOUT_MS / 1000, budget_s) * 1000)

    async def _guarded():
        async with app.state.render_semaphore:
            return await render(app.state.browser, url, nav_timeout_ms=nav_timeout_ms)

    try:
        r = await asyncio.wait_for(_guarded(), timeout=budget_s)
    except TimeoutError:
        return PageView(ok=False, final_url=url, raw_text="", error="시간 초과")
    return PageView(ok=r.ok, final_url=r.final_url or url, raw_text=r.raw_text, error=r.error)


def _decode_image(image_base64: str) -> bytes:
    if len(image_base64) > _MAX_IMAGE_BASE64_CHARS:
        raise HTTPException(413, f"사진이 너무 큽니다(최대 {config.IDENTIFY_MAX_IMAGE_BYTES} bytes)")
    try:
        image = base64.b64decode(image_base64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(422, "image_base64가 올바른 base64가 아닙니다") from None
    if not image:
        raise HTTPException(422, "사진이 비어 있습니다")
    if len(image) > config.IDENTIFY_MAX_IMAGE_BYTES:
        raise HTTPException(413, f"사진이 너무 큽니다(최대 {config.IDENTIFY_MAX_IMAGE_BYTES} bytes)")
    return image


@app.post("/identify-tag")
async def identify_tag(req: IdentifyTagRequest):
    image = _decode_image(req.image_base64)
    started = now_ms()

    def time_left() -> float:
        return config.IDENTIFY_TIMEOUT_S - (now_ms() - started) / 1000

    stages: dict[str, int] = {}  # 단계별 걸린 시간(ms) — 못 찾았을 때 어디서 시간을 썼는지 로그로 본다

    async def timed(name: str, coro):
        t = now_ms()
        try:
            return await coro
        finally:
            stages[name] = stages.get(name, 0) + now_ms() - t

    async def gemini_once(fn, *args) -> ProviderResult:
        # AppSync 30초 한도 안에서 끝나야 하므로 429 재시도는 1번만, 그리고 남은 시간 안에 끝날
        # 때만 기다린다(retryDelay가 더 길면 바로 실패 → 태그 결과라도 not_found로 돌려줌).
        call = partial(fn, max_retries=1, max_retry_wait_s=max(0.0, time_left() - 2.0))
        result, _ = await _run_gemini(call, *args)
        return result

    try:
        outcome = await asyncio.wait_for(
            identify(
                image, req.mime_type,
                read_tag=lambda img, mime: timed("read_tag", gemini_once(call_gemini_tag, img, mime)),
                search=lambda tag: timed("search", gemini_once(call_gemini_search, tag)),
                render_page=lambda url: timed("render", _render_for_identify(url, time_left() - 1.0)),
                time_left=time_left,
            ),
            timeout=config.IDENTIFY_TIMEOUT_S,
        )
    except TimeoutError:
        raise HTTPException(504, f"요청 처리 시간이 {config.IDENTIFY_TIMEOUT_S}초를 넘어 취소됨") from None
    except IdentifyError as exc:
        raise HTTPException(502, str(exc)) from exc
    except Exception as exc:
        logger.exception("identify-tag 알 수 없는 오류")
        raise HTTPException(500, f"{type(exc).__name__}: {exc}") from exc

    total_ms = now_ms() - started
    # 한 줄 요약 로그(사진은 남기지 않음): 무엇을 읽고, 어디를 열어 봤고, 왜 떨어졌는지.
    logger.info(
        "[identify] %s (%dms, 단계 %s) brand=%r code=%r other=%r official=%r note=%r checked=%s",
        outcome.status, total_ms, stages, outcome.tag.get("brand"), outcome.tag.get("product_code"),
        outcome.tag.get("other_codes"), outcome.official_domain, outcome.note,
        [(c["url"], c["source"], c["verified"], c["reason"]) for c in outcome.checked],
    )
    return {**outcome.to_dict(), "metrics": {"total_elapsed_ms": total_ms, "stages_ms": stages}}


@app.get("/healthz")
async def healthz():
    return {"ok": True, "browser_connected": app.state.browser.is_connected()}
