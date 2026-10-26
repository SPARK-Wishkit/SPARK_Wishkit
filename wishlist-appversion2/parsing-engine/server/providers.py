"""
Gemini 호출 래퍼.

`engine-ai-prototype/providers.py`에서 포팅. 호출 방식(시스템 프롬프트 분리, JSON 스키마 강제,
429 응답의 retryDelay를 파싱해서 따르는 재시도)은 원본과 동일하다. RPM/TPM 같은 한도는 코드에
박혀 있지 않고, 동시 호출 수는 main.py의 세마포어(config.GEMINI_MAX_CONCURRENCY)로 제한한다.

원본에 있던 Anthropic/OpenAI 호출 함수(bakeoff 비교용)는 서버에서 한 번도 호출되지 않아
뺐다 — 필요하면 engine-ai-prototype 쪽 원본을 참고할 것.

동기 함수로 남겨둔 이유: google-genai 동기 클라이언트가 프로토타입에서 검증된 경로라서다.
서버에서는 `asyncio.to_thread()`로 감싸 호출하므로 이벤트 루프를 막지 않는다.
"""
from __future__ import annotations

import json
import logging
import re
import time
from dataclasses import dataclass
from functools import lru_cache

import config
from metrics import now_ms
from prompts import (
    OUTPUT_JSON_SCHEMA,
    SYSTEM_PROMPT,
    build_user_prompt,
    build_vision_user_prompt,
)

logger = logging.getLogger("extract-server")


@dataclass
class ProviderResult:
    provider: str
    model: str
    ok: bool
    data: dict | None
    elapsed_ms: int
    error: str | None = None


def to_gemini_schema(schema: dict) -> dict:
    """표준 JSON Schema(`"type": ["string", "null"]`처럼 null을 유니언으로 표현)를
    google-genai가 요구하는 OpenAPI 3.0 서브셋(`nullable: true`)으로 변환한다."""
    out: dict = {}
    t = schema.get("type")
    if isinstance(t, list):
        non_null = [x for x in t if x != "null"]
        out["type"] = (non_null[0] if non_null else "string").upper()
        if "null" in t:
            out["nullable"] = True
    elif t:
        out["type"] = t.upper()
    for key in ("enum", "required"):
        if key in schema:
            out[key] = schema[key]
    if "properties" in schema:
        out["properties"] = {k: to_gemini_schema(v) for k, v in schema["properties"].items()}
    if "items" in schema:
        out["items"] = to_gemini_schema(schema["items"])
    return out


# 스키마와 생성 설정은 요청마다 바뀌지 않으므로 모듈 로드 시 한 번만 만든다.
_GENERATION_CONFIG = {
    "system_instruction": SYSTEM_PROMPT,
    "response_mime_type": "application/json",
    "response_schema": to_gemini_schema(OUTPUT_JSON_SCHEMA),
}

_RETRY_DELAY_RE = re.compile(r"retryDelay['\"]?\s*:\s*['\"]?(\d+(?:\.\d+)?)s")


def _retry_delay_seconds(exc: Exception, default: float = 20.0) -> float:
    """429 응답 본문의 retryDelay를 파싱한다. 못 찾으면 default."""
    m = _RETRY_DELAY_RE.search(str(exc))
    return float(m.group(1)) if m else default


def _is_rate_limit(exc: Exception) -> bool:
    msg = str(exc)
    return "429" in msg or "RESOURCE_EXHAUSTED" in msg


@lru_cache(maxsize=1)
def _client():
    """genai.Client를 프로세스당 한 번만 만든다(원본은 호출마다 새로 생성했음).
    SDK는 지연 임포트 — 테스트 환경에서 패키지 없이도 이 모듈을 import할 수 있게."""
    from google import genai

    return genai.Client(api_key=config.GEMINI_API_KEY)


def generate(
    label: str,
    contents,
    max_retries: int,
    *,
    generation_config=None,
    model: str | None = None,
    parse_json: bool = True,
    max_retry_wait_s: float | None = None,
) -> ProviderResult:
    """Gemini 호출 + 429 재시도 공통 루프. 상품 추출(텍스트/비전)과 태그 찾기(tag_identify.py)가
    같이 쓴다.

    - `generation_config`/`model`을 안 넘기면 상품 추출용 기본값(_GENERATION_CONFIG,
      config.GEMINI_MODEL)을 쓴다.
    - `parse_json=False`면 응답 객체 전체를 data["response"]에 담는다(검색 그라운딩처럼 JSON이
      아닌 응답에서 grounding_metadata까지 읽어야 할 때).
    - `max_retry_wait_s`: 429 재시도 전에 기다려야 할 시간이 이보다 길면 기다리지 않고 바로 실패로
      돌려준다. 시간 예산이 빠듯한 요청(/identify-tag, 25초)에서 retryDelay(보통 20초 안팎)만큼
      자다가 전체 요청이 504로 끝나는 걸 막는다. None이면 제한 없음(기존 동작)."""
    model = model or config.GEMINI_MODEL
    gen_config = _GENERATION_CONFIG if generation_config is None else generation_config
    started = now_ms()
    try:
        for attempt in range(max_retries + 1):
            try:
                resp = _client().models.generate_content(
                    model=model, contents=contents, config=gen_config
                )
                data = json.loads(resp.text) if parse_json else {"response": resp}
                return ProviderResult(label, model, True, data, now_ms() - started)
            except Exception as exc:
                if not _is_rate_limit(exc) or attempt == max_retries:
                    raise
                wait = _retry_delay_seconds(exc) + 1.0  # 서버가 알려준 지연 + 여유 1초
                if max_retry_wait_s is not None and wait > max_retry_wait_s:
                    raise
                logger.warning("[%s] 429 rate limit — %.0f초 대기 후 재시도 (%d/%d)",
                               label, wait, attempt + 1, max_retries)
                time.sleep(wait)
    except Exception as exc:  # noqa: BLE001 — 실패는 예외 대신 결과로 표현
        return ProviderResult(label, model, False, None, now_ms() - started,
                              error=f"{type(exc).__name__}: {exc}")
    raise AssertionError("unreachable")  # 루프는 항상 return 또는 raise로 끝난다


def call_gemini(cleaned_html: str, *, max_retries: int = config.GEMINI_MAX_RETRIES) -> ProviderResult:
    """1차 추출: 정제된 HTML을 텍스트로 보낸다."""
    return generate("gemini", build_user_prompt(cleaned_html), max_retries)


def call_gemini_vision(
    screenshot: bytes, image_candidates: list[str], *, max_retries: int = config.GEMINI_MAX_RETRIES
) -> ProviderResult:
    """스크린샷 폴백: 1차 결과가 ambiguous일 때만 main.py가 호출한다. 스크린샷으로는 실제
    이미지 URL을 알 수 없으므로 1차 렌더링의 이미지 후보 목록을 같이 넘긴다."""
    from google.genai import types

    contents = [
        types.Part.from_bytes(data=screenshot, mime_type="image/jpeg"),
        build_vision_user_prompt(image_candidates),
    ]
    return generate("gemini_vision", contents, max_retries)
