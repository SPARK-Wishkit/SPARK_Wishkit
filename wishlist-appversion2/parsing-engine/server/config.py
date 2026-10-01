"""서버 설정값 — 전부 환경변수로 오버라이드 가능하게 뺐다(요구사항 7)."""
from __future__ import annotations

import os

# 요청 하나(렌더링 + Gemini 호출 + 필요시 스크린샷 폴백)의 전체 타임아웃. 이 시간을
# 넘기면 504로 응답하고 해당 요청을 취소한다 — 서버 전체나 다른 요청은 영향받지 않는다.
EXTRACT_TIMEOUT_S = float(os.environ.get("EXTRACT_TIMEOUT_S", "45"))

# Playwright page.goto()의 네비게이션 타임아웃 (render.py에 전달).
RENDER_NAV_TIMEOUT_MS = int(os.environ.get("RENDER_NAV_TIMEOUT_MS", "20000"))

# 동시에 실행 가능한 render() 호출 수 상한(세마포어). REPORT_2026-09-19.md 2절에서 발견:
# render()에는 원래 동시 실행 제한이 없어서, 트래픽이 몰리면 브라우저 컨텍스트가 무제한으로
# 늘어날 수 있었다(동시 요청 1건당 peak_rss +400~650MB 실측 — config.py 어딘가 상한이
# 없으면 메모리가 선형으로 계속 늘어난다). GEMINI_MAX_CONCURRENCY와 별개로 렌더링 단계
# 자체를 제한해서 컨텍스트 수를 상한 이하로 유지한다.
RENDER_MAX_CONCURRENCY = int(os.environ.get("RENDER_MAX_CONCURRENCY", "6"))

# Gemini 429 재시도 최대 횟수 (providers.py의 DEFAULT_MAX_RETRIES와 동일 — 여기 있는 값은
# main.py가 명시적으로 넘길 때 쓰고, providers.py 쪽 기본값도 같은 환경변수를 본다).
GEMINI_MAX_RETRIES = int(os.environ.get("GEMINI_MAX_RETRIES", "4"))

# 동시에 실행 가능한 Gemini 호출 수 상한(세마포어). 원본 providers.py엔 RPM/TPM 같은 고정
# 한도가 코드로 박혀있지 않다(429의 retryDelay를 그때그때 따름) — 그 대신 여기서 "서버가
# 한 번에 얼마나 많은 요청을 동시에 Gemini에 밀어넣을지"를 직접 제어한다.
# 2026-09-29 Tier 1(유료) 전환 확인(RPM 4,000/TPM 4,000,000/RPD 150,000)에 맞춰 3→6으로
# 올림 — RENDER_MAX_CONCURRENCY(6)와 맞춰서, Gemini 쪽이 렌더링보다 더 타이트한 병목이
# 되지 않게 함. 무료 티어(RPM 15) 시절 기본값 3에 대한 근거는 REPORT_FARGATE_VALIDATION_
# 2026-09-24.md §4 참고 — 그때는 태스크를 여러 개로 늘려도 계정 전체 RPM 한도를 나눠 쓰는
# 것이라 병목이 그대로였다.
GEMINI_MAX_CONCURRENCY = int(os.environ.get("GEMINI_MAX_CONCURRENCY", "6"))

# 요청별 peak RSS 샘플링 주기 (metrics.py).
RSS_SAMPLE_INTERVAL_MS = int(os.environ.get("RSS_SAMPLE_INTERVAL_MS", "100"))

# 서버 바인드 주소/포트.
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8000"))
