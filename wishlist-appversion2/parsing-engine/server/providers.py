"""
AI 제공자 호출 래퍼 (provider-agnostic).

`engine-ai-prototype/providers.py`를 포팅했다. 호출 로직(스키마 변환, 429 재시도)은
그대로다 — 딱 한 가지만 추가했다: 요구사항 7("유료 티어를 쓸 경우를 대비해 한도를
환경변수로 뺄 수 있으면 빼라")에 맞춰 `max_retries`의 기본값을 `GEMINI_MAX_RETRIES`
환경변수로 뺐다. 원본에는 분당 요청수(RPM)·토큰수(TPM) 같은 한도가 코드에 하드코딩돼
있지 않다 — 429 응답의 `retryDelay`를 그때그때 파싱해서 따르는 방식이라 원래도
티어 무관하게 동작한다(그래서 이 부분엔 추가로 뺄 게 없었다). 동시 호출 수 제한은
`config.py`의 `GEMINI_MAX_CONCURRENCY`(세마포어)로 별도 처리한다 — main.py 참고.

이 파일은 동기(sync) 함수로 남겨뒀다 — google-genai SDK의 동기 클라이언트가 이미
engine-ai-prototype에서 실제로 검증된 코드라, 서버 쪽에서는 이 함수들을
`asyncio.to_thread()`로 감싸서 호출한다(별도 스레드에서 실행돼 이벤트 루프를 막지
않음). 비동기 SDK 경로로 새로 옮기는 건 검증 안 된 코드를 새로 추가하는 것과 같아서
이번엔 하지 않았다.
"""
from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass

from prompts import (
    OUTPUT_JSON_SCHEMA,
    SYSTEM_PROMPT,
    build_user_prompt,
    build_vision_user_prompt,
)

DEFAULT_MAX_RETRIES = int(os.environ.get("GEMINI_MAX_RETRIES", "4"))


@dataclass
class ProviderResult:
    provider: str
    model: str
    ok: bool
    data: dict | None
    elapsed_ms: int
    error: str | None = None


def _now_ms() -> int:
    return int(time.monotonic() * 1000)


def call_anthropic(cleaned_html: str) -> ProviderResult:
    model = os.environ.get("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
    started = _now_ms()
    try:
        import anthropic  # 지연 임포트 — 키 없는 provider는 SDK 미설치여도 되게

        client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
        resp = client.messages.create(
            model=model,
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            tools=[
                {
                    "name": "extract_product",
                    "description": "추출한 상품 정보를 구조화된 형태로 반환한다.",
                    "input_schema": OUTPUT_JSON_SCHEMA,
                }
            ],
            tool_choice={"type": "tool", "name": "extract_product"},
            messages=[{"role": "user", "content": build_user_prompt(cleaned_html)}],
        )
        data = None
        for block in resp.content:
            if getattr(block, "type", None) == "tool_use":
                data = block.input
                break
        if data is None:
            return ProviderResult("anthropic", model, False, None, _now_ms() - started,
                                   error="tool_use 블록을 찾지 못함 — 응답 구조 확인 필요")
        return ProviderResult("anthropic", model, True, data, _now_ms() - started)
    except Exception as exc:  # noqa: BLE001
        return ProviderResult("anthropic", model, False, None, _now_ms() - started,
                               error=f"{type(exc).__name__}: {exc}")


def call_openai(cleaned_html: str) -> ProviderResult:
    model = os.environ.get("OPENAI_MODEL", "gpt-5.4-mini")
    started = _now_ms()
    try:
        from openai import OpenAI  # 지연 임포트

        client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": build_user_prompt(cleaned_html)},
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "extract_product",
                    "schema": OUTPUT_JSON_SCHEMA,
                    "strict": True,
                },
            },
        )
        content = resp.choices[0].message.content
        data = json.loads(content)
        return ProviderResult("openai", model, True, data, _now_ms() - started)
    except Exception as exc:  # noqa: BLE001
        return ProviderResult("openai", model, False, None, _now_ms() - started,
                               error=f"{type(exc).__name__}: {exc}")


def _to_gemini_schema(schema: dict) -> dict:
    """OUTPUT_JSON_SCHEMA(표준 JSON Schema, "type": ["string", "null"]처럼 null을 유니언으로
    표현)를 google-genai가 요구하는 OpenAPI 3.0 서브셋 형식으로 변환한다."""
    if "type" in schema:
        t = schema["type"]
        if isinstance(t, list):
            non_null = [x for x in t if x != "null"]
            gemini_type = (non_null[0] if non_null else "string").upper()
            nullable = "null" in t
        else:
            gemini_type = t.upper()
            nullable = False
    else:
        gemini_type = None
        nullable = False

    out: dict = {}
    if gemini_type:
        out["type"] = gemini_type
    if nullable:
        out["nullable"] = True
    if "enum" in schema:
        out["enum"] = schema["enum"]
    if "properties" in schema:
        out["properties"] = {k: _to_gemini_schema(v) for k, v in schema["properties"].items()}
    if "required" in schema:
        out["required"] = schema["required"]
    if "items" in schema:
        out["items"] = _to_gemini_schema(schema["items"])
    return out


_RETRY_DELAY_RE = re.compile(r"retryDelay['\"]?\s*:\s*['\"]?(\d+(?:\.\d+)?)s")


def _extract_retry_delay_seconds(exc: Exception, default: float = 20.0) -> float:
    """429 응답 본문에 실제로 들어있는 retryDelay를 최대한 파싱해서 쓴다. 못 찾으면
    default로 폴백."""
    m = _RETRY_DELAY_RE.search(str(exc))
    if m:
        return float(m.group(1))
    return default


def call_gemini(cleaned_html: str, *, max_retries: int = DEFAULT_MAX_RETRIES) -> ProviderResult:
    model = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
    started = _now_ms()
    last_exc: Exception | None = None
    try:
        from google import genai  # 지연 임포트 (google-genai 패키지)

        client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
        for attempt in range(max_retries + 1):
            try:
                # system prompt는 contents 리스트에 섞지 않고 system_instruction으로 분리 —
                # 이전 방식(contents=[SYSTEM_PROMPT, user_prompt])은 SDK가 "AFC(자동 함수 호출)
                # 직접 사용은 권장하지 않음" 경고를 띄우는 원인이기도 했다(실측으로 확인).
                resp = client.models.generate_content(
                    model=model,
                    contents=build_user_prompt(cleaned_html),
                    config={
                        "system_instruction": SYSTEM_PROMPT,
                        "response_mime_type": "application/json",
                        "response_schema": _to_gemini_schema(OUTPUT_JSON_SCHEMA),
                    },
                )
                data = json.loads(resp.text)
                return ProviderResult("gemini", model, True, data, _now_ms() - started)
            except Exception as exc:
                last_exc = exc
                is_rate_limit = "429" in str(exc) or "RESOURCE_EXHAUSTED" in str(exc)
                if not is_rate_limit or attempt == max_retries:
                    raise
                delay = _extract_retry_delay_seconds(exc)
                print(f"    [gemini] 429 rate limit — {delay:.0f}초 대기 후 재시도 "
                      f"({attempt + 1}/{max_retries})")
                time.sleep(delay + 1.0)  # 서버가 알려준 지연 + 여유 1초
        raise last_exc  # 방어적 — 위 루프가 항상 return/raise로 끝나지만 린터 안심용
    except Exception as exc:  # noqa: BLE001
        return ProviderResult("gemini", model, False, None, _now_ms() - started,
                               error=f"{type(exc).__name__}: {exc}")


def call_gemini_vision(
    screenshot: bytes, image_candidates: list[str], *, max_retries: int = DEFAULT_MAX_RETRIES
) -> ProviderResult:
    """"텍스트 우선, 애매하면 스크린샷 폴백" — 1차 텍스트 추출이 ambiguous일 때만 호출된다.
    call_gemini()와 거의 동일하지만 contents에 cleaned_html 대신 스크린샷 이미지 파트를
    넣는다."""
    model = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
    started = _now_ms()
    last_exc: Exception | None = None
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
        for attempt in range(max_retries + 1):
            try:
                resp = client.models.generate_content(
                    model=model,
                    contents=[
                        types.Part.from_bytes(data=screenshot, mime_type="image/jpeg"),
                        build_vision_user_prompt(image_candidates),
                    ],
                    config={
                        "system_instruction": SYSTEM_PROMPT,
                        "response_mime_type": "application/json",
                        "response_schema": _to_gemini_schema(OUTPUT_JSON_SCHEMA),
                    },
                )
                data = json.loads(resp.text)
                return ProviderResult("gemini_vision", model, True, data, _now_ms() - started)
            except Exception as exc:
                last_exc = exc
                is_rate_limit = "429" in str(exc) or "RESOURCE_EXHAUSTED" in str(exc)
                if not is_rate_limit or attempt == max_retries:
                    raise
                delay = _extract_retry_delay_seconds(exc)
                print(f"    [gemini_vision] 429 rate limit — {delay:.0f}초 대기 후 재시도 "
                      f"({attempt + 1}/{max_retries})")
                time.sleep(delay + 1.0)
        raise last_exc
    except Exception as exc:  # noqa: BLE001
        return ProviderResult("gemini_vision", model, False, None, _now_ms() - started,
                               error=f"{type(exc).__name__}: {exc}")


# 활성화 조건: 해당 API 키 환경변수가 설정돼 있으면만 그 provider를 돌린다.
ALL_PROVIDERS = {
    "anthropic": ("ANTHROPIC_API_KEY", call_anthropic),
    "openai": ("OPENAI_API_KEY", call_openai),
    "gemini": ("GEMINI_API_KEY", call_gemini),
}


def active_providers() -> list[str]:
    return [name for name, (env_key, _fn) in ALL_PROVIDERS.items() if os.environ.get(env_key)]
