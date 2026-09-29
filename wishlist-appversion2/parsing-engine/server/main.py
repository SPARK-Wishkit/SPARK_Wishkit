"""
Wishkit 상품 추출 엔진 — AI 완전 의존 방식 서버 (프로토타입 → 실제 서버 포팅).

engine-ai-prototype(설계안 0절, 2026-09-18 결정: 몰별 DOM 규칙을 전부 폐기하고 서버 AI가
상품 페이지를 읽어 구조화 추출)에서 golden_catalog.json 36개 상품으로 검증을 마친 파이프라인
(render.py의 Playwright 렌더링 → providers.py의 Gemini 호출/재시도/스크린샷 폴백 →
prompts.py의 프롬프트/정책)을 실제 HTTP 요청을 받는 서버로 감싼 것.

흐름: POST /extract {url} → 렌더링(공유 브라우저, 새 컨텍스트) → cleaned_html을 Gemini에
전달 → ambiguous면 스크린샷을 Gemini 비전 모드로 재시도 → 그라운딩 체크 → JSON 응답.

실행: `uvicorn main:app --host 0.0.0.0 --port 8000` (requirements.txt 설치 + .env에
GEMINI_API_KEY 필요 — .env.example 참고).
"""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI, HTTPException
from playwright.async_api import async_playwright
from pydantic import BaseModel, HttpUrl

import config
from cache import CachedExtraction, NoOpCache, normalize_cache_key
from compare import grounding_check
from metrics import PeakRSSSampler, now_ms
from providers import call_gemini, call_gemini_vision
from render import render

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("extract-server")


class ExtractRequest(BaseModel):
    url: HttpUrl


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 요구사항 4: 브라우저는 요청마다 새로 띄우지 않고 앱 생명주기 동안 재사용한다.
    playwright = await async_playwright().start()
    try:
        browser = await playwright.chromium.launch(channel="chrome", headless=True)
    except Exception:  # noqa: BLE001 — 크롬 채널이 없는 환경용 의도적 폴백
        browser = await playwright.chromium.launch(headless=True)
    app.state.playwright = playwright
    app.state.browser = browser
    app.state.gemini_semaphore = asyncio.Semaphore(config.GEMINI_MAX_CONCURRENCY)
    app.state.render_semaphore = asyncio.Semaphore(config.RENDER_MAX_CONCURRENCY)
    app.state.cache = NoOpCache()  # 요구사항 5: 실제 캐시 백엔드는 아직 미구현
    logger.info(
        "서버 시작 — 브라우저 준비 완료 (GEMINI_MAX_CONCURRENCY=%s, RENDER_MAX_CONCURRENCY=%s, EXTRACT_TIMEOUT_S=%s)",
        config.GEMINI_MAX_CONCURRENCY, config.RENDER_MAX_CONCURRENCY, config.EXTRACT_TIMEOUT_S,
    )
    yield
    await browser.close()
    await playwright.stop()
    logger.info("서버 종료 — 브라우저 정리 완료")


app = FastAPI(title="wishkit-ai-extraction-engine", lifespan=lifespan)


class ExtractPipelineError(Exception):
    """렌더링 실패/차단처럼 "요청 자체가 처리 불가"인 경우에만 쓴다. ambiguous:true는
    정상적인 결과이지 에러가 아니다."""

    def __init__(self, status_code: int, detail: str):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


async def _run_gemini(app_state, fn, *args) -> providers.ProviderResult:  # noqa: F821
    # 요구사항 7과 연결: 동시에 Gemini에 밀어넣는 요청 수를 세마포어로 제한한다(무료 티어
    # 실질 처리량 상한인 분당 4~5건 근처에서 429가 몰아치는 걸 완화). call_gemini*는 동기
    # 함수(내부에서 time.sleep으로 재시도)라 to_thread로 감싸서 이벤트 루프를 막지 않는다.
    async with app_state.gemini_semaphore:
        return await asyncio.to_thread(fn, *args)


async def _extract(url: str) -> dict:
    t_start = now_ms()
    cache_key = normalize_cache_key(url)
    cached = await app.state.cache.get(cache_key)
    if cached is not None:
        return {**cached.data, "metrics": {**cached.data.get("metrics", {}), "cache_hit": True}}

    t_render_start = now_ms()
    async with app.state.render_semaphore:
        r = await render(app.state.browser, url, nav_timeout_ms=config.RENDER_NAV_TIMEOUT_MS)
    render_elapsed_ms = now_ms() - t_render_start

    if r.error:
        raise ExtractPipelineError(502, f"렌더링 오류: {r.error}")
    if r.blocked:
        raise ExtractPipelineError(502, f"상품 페이지 접근이 차단됨(final_url={r.final_url})")
    if not r.ok:
        raise ExtractPipelineError(502, "렌더링 실패(원인 불명)")

    t_gemini_start = now_ms()
    text_result = await _run_gemini(app.state, call_gemini, r.cleaned_html)
    text_elapsed_ms = now_ms() - t_gemini_start

    if not text_result.ok or not text_result.data:
        raise ExtractPipelineError(502, f"AI 호출 실패: {text_result.error}")

    extracted = text_result.data
    screenshot_fallback_used = False
    vision_elapsed_ms = 0

    if extracted.get("ambiguous") and r.screenshot:
        t_vision_start = now_ms()
        vision_result = await _run_gemini(app.state, call_gemini_vision, r.screenshot, r.image_candidates)
        vision_elapsed_ms = now_ms() - t_vision_start
        if vision_result.ok and vision_result.data:
            extracted = vision_result.data
            screenshot_fallback_used = True
        else:
            logger.warning("스크린샷 폴백 실패(%s) — 텍스트 결과를 그대로 사용", vision_result.error)

    grounding = grounding_check(extracted, r.raw_text, r.image_candidates)

    total_elapsed_ms = now_ms() - t_start
    response = {
        **extracted,
        "grounding": grounding,
        "screenshot_fallback_used": screenshot_fallback_used,
        "render": {"ok": r.ok, "blocked": r.blocked, "final_url": r.final_url},
        "metrics": {
            "total_elapsed_ms": total_elapsed_ms,
            "render_elapsed_ms": render_elapsed_ms,
            "gemini_text_elapsed_ms": text_elapsed_ms,
            "gemini_vision_elapsed_ms": vision_elapsed_ms,
            "cache_hit": False,
        },
    }
    await app.state.cache.set(cache_key, CachedExtraction(data=response, cached_at_ms=now_ms()), ttl_seconds=3600)
    return response


@app.post("/extract")
async def extract(req: ExtractRequest):
    url = str(req.url)
    async with PeakRSSSampler(interval_ms=config.RSS_SAMPLE_INTERVAL_MS) as sampler:
        try:
            result = await asyncio.wait_for(_extract(url), timeout=config.EXTRACT_TIMEOUT_S)
        except asyncio.TimeoutError:
            raise HTTPException(
                status_code=504,
                detail=f"요청 처리 시간이 {config.EXTRACT_TIMEOUT_S}초를 넘어 취소됨: {url}",
            )
        except ExtractPipelineError as exc:
            raise HTTPException(status_code=exc.status_code, detail=exc.detail)
        except Exception as exc:
            logger.exception("알 수 없는 오류: %s", url)
            raise HTTPException(status_code=500, detail=f"{type(exc).__name__}: {exc}")

    result["metrics"]["peak_rss_mb"] = round(sampler.peak_rss_mb, 1)
    return result


@app.get("/healthz")
async def healthz():
    return {"ok": True, "browser_connected": app.state.browser.is_connected()}
