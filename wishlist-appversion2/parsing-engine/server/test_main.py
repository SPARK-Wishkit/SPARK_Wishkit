"""
API 계층 스모크 테스트. 실제 Playwright 렌더링/Gemini 호출까지 포함하는 end-to-end 검증은
여기서 하지 않는다 — 그건 `tools/golden_regression_check.py`로 골든셋 36개를 실제 서버에
쏴서 이미 확인했다(회귀 없음, 완전 일치 22/36=61%, 그라운딩 28/36=78% — run6 대비 회귀
없음, 상세 원인 분석은 보고서 참고). 여기서는 FastAPI 앱 자체(요청 검증, lifespan으로
브라우저가 실제로 뜨는지, healthz)만 빠르게 확인한다 — 이것도 실제 Playwright 브라우저를
띄우므로(모킹하지 않음), 헤드리스 크롬이 설치돼 있어야 통과한다.
"""
from fastapi.testclient import TestClient

from main import app


def test_healthz_reports_browser_connected():
    with TestClient(app) as client:
        resp = client.get("/healthz")
        assert resp.status_code == 200
        body = resp.json()
        assert body["ok"] is True
        assert body["browser_connected"] is True


def test_extract_rejects_invalid_url():
    with TestClient(app) as client:
        resp = client.post("/extract", json={"url": "not-a-url"})
        assert resp.status_code == 422  # pydantic HttpUrl 검증에서 걸러짐 — 브라우저/Gemini 호출 전
