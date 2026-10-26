"""서버 설정값 — 전부 환경변수로 오버라이드 가능하다."""
from __future__ import annotations

import os

from dotenv import load_dotenv

# .env는 설정을 읽기 전에 여기서 로드한다 — 어떤 모듈이 config를 먼저 import하든 순서가 안 꼬이게.
load_dotenv()


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


# Gemini 인증/모델. providers.py가 여기 값만 본다.
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")

# 요청 하나(렌더링 + Gemini 호출 + 필요시 스크린샷 폴백)의 전체 타임아웃. 넘기면 504로
# 응답하고 그 요청만 취소한다.
EXTRACT_TIMEOUT_S = float(os.environ.get("EXTRACT_TIMEOUT_S", "45"))

# Playwright page.goto()의 네비게이션 타임아웃.
RENDER_NAV_TIMEOUT_MS = _int("RENDER_NAV_TIMEOUT_MS", 20000)

# 동시 render() 호출 수 상한. 동시 요청 1건당 peak RSS가 +400~650MB 늘어나는 게 실측돼서
# (REPORT_2026-09-19.md 2절) 브라우저 컨텍스트 수를 이 값 이하로 묶는다.
RENDER_MAX_CONCURRENCY = _int("RENDER_MAX_CONCURRENCY", 6)

# Gemini 429 재시도 최대 횟수.
GEMINI_MAX_RETRIES = _int("GEMINI_MAX_RETRIES", 4)

# 동시 Gemini 호출 수 상한. 2026-09-29 Tier 1(유료) 전환에 맞춰 3→6으로 올려
# RENDER_MAX_CONCURRENCY와 맞췄다. 무료 티어면 3 권장(근거: REPORT_FARGATE_VALIDATION_
# 2026-09-24.md §4 — 태스크를 늘려도 계정 전체 RPM을 나눠 쓰므로 병목이 그대로였음).
GEMINI_MAX_CONCURRENCY = _int("GEMINI_MAX_CONCURRENCY", 6)

# 요청별 peak RSS 샘플링 주기 (metrics.py).
RSS_SAMPLE_INTERVAL_MS = _int("RSS_SAMPLE_INTERVAL_MS", 100)

# ── 태그 사진으로 찾기 (POST /identify-tag, tag_identify.py) ──
# 태그 읽기(비전)·검색(Google 검색 그라운딩)에 쓸 모델. 안 채우면 GEMINI_MODEL과 같다.
# 검색 그라운딩은 모델마다 지원 여부·요금이 다르니 바꿀 때 Gemini 문서를 확인할 것.
GEMINI_TAG_MODEL = os.environ.get("GEMINI_TAG_MODEL", "") or GEMINI_MODEL
GEMINI_SEARCH_MODEL = os.environ.get("GEMINI_SEARCH_MODEL", "") or GEMINI_MODEL

# 요청 하나(태그 읽기 + 검색 + 후보 페이지 확인)의 전체 타임아웃.
# ⚠️ 앱 → AppSync → Lambda 경로는 AppSync가 30초에 끊는다(늘릴 수 없는 한도). 그래서 Lambda의
# fetch 타임아웃(27초)보다 짧게 25초로 둔다. 시간이 모자라면 후보 페이지 확인을 덜 하고
# not_found로 끝낸다(앱은 태그 정보로 직접 입력 화면을 보여줌).
IDENTIFY_TIMEOUT_S = float(os.environ.get("IDENTIFY_TIMEOUT_S", "25"))

# 검색 후보 중 실제로 렌더링해서 품번을 확인해 볼 최대 개수.
IDENTIFY_MAX_CANDIDATES = _int("IDENTIFY_MAX_CANDIDATES", 3)

# 업로드 사진 최대 크기(바이트, 디코딩 후). 앱은 1280px·JPEG 75%로 줄여서 보낸다.
IDENTIFY_MAX_IMAGE_BYTES = _int("IDENTIFY_MAX_IMAGE_BYTES", 4 * 1024 * 1024)
