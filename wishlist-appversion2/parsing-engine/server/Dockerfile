# Playwright 공식 이미지 사용 — 브라우저/OS 의존성을 직접 설치하는 것보다 안전
# (playwright.async_api 버전과 이미지에 내장된 Chromium 버전이 항상 맞게 관리됨).
# 태그는 requirements.txt가 실제로 설치하는 playwright 버전(1.63.0)과 반드시 맞춰야 한다 —
# 버전이 어긋나면 "Executable doesn't exist" 류의 브라우저 실행 오류가 난다.
FROM mcr.microsoft.com/playwright/python:v1.63.0-noble

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# render.py가 channel="chrome"을 우선 시도하고 실패하면 headless=True(Chromium)로
# 폴백하므로(render.py launch_browser 참고), 베이스 이미지의 Chromium만 있으면 충분하다.
# 별도로 playwright install을 다시 돌리지 않는다 — 이미지에 이미 매칭된 브라우저가 있다.

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
