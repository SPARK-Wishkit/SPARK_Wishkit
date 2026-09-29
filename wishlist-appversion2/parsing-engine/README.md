# parsing-engine — AI 완전 의존 상품 추출 서버

`ENGINE_DEVELOPMENT_HANDOFF.md` 0.9절에서 삭제됐던 `parsing-engine/` 폴더를 다른 방향으로
되살린 것이다 — 이전 버전(DOM 규칙 기반 Python 폴백)과는 무관하다. 이번 버전은 **몰별 규칙이
전혀 없고, 상품 페이지를 렌더링해서 AI(Gemini)에게 통째로 읽혀 이름/가격/이미지를 뽑는다.**

**이관 메모**: 이 폴더는 원래 `soft-studio-team/2026-softstudio-project` 저장소의
`feat/ai-extraction-server` 브랜치(커밋 `ea81107`)에서 개발·검증됐고, 이 저장소로 그대로
이관됐다. AWS Fargate 실측 검증(서울 리전, 4GB/6GB 태스크, 단일/수평 확장)과 Gemini
Tier 1 전환까지 끝난 상태이며, 그 과정은 `REPORT_2026-09-19.md`·
`REPORT_FARGATE_VALIDATION_2026-09-24.md`에 그대로 남아있다.

## 배경 — 반드시 먼저 읽을 것

이 폴더가 만들어진 시점(2026-09-19)에 `main` 브랜치의 `ENGINE_DEVELOPMENT_HANDOFF.md`는
여전히 "Python 서버 폴백은 채택하지 않음, WebView 우선"이라고 적혀 있었다(마지막 갱신
2026-08-21). 이 서버는 그 결정을 뒤집는 **2026-09-18 새 결정**("서버 AI 완전 의존" —
`engine-ai-prototype/design-doc-snapshot-2026-09-18.md` 0절)에 따라 만들어졌다. 두 문서가
당분간 서로 다른 이야기를 할 수 있으니, 이 폴더를 보고 헷갈리면 그 두 문서(및
`ENGINE_DEVELOPMENT_HANDOFF.md`에 새로 추가된 노트)를 먼저 대조해볼 것.

## 이 폴더와 `engine-ai-prototype`의 관계

`engine-ai-prototype/`(이 저장소 밖, 별도 폴더)은 이 파이프라인의 **원본 프로토타입**이다 —
로컬 배치 스크립트(`bakeoff.py`)로 골든셋 36개 상품에 대해 정확도만 검증했다(완전 일치
21/36=58%, 그라운딩 통과 31/36=86% — `bakeoff_results_run6_final.json`). 이 폴더
(`server/`)는 그 검증된 로직(`render.py`/`prompts.py`/`providers.py`/`compare.py`)을 실제
HTTP 요청에 응답하는 서버로 감싼 것 — 로직 자체(프롬프트 문구, few-shot, 가격 정책,
그라운딩 체크)는 바뀐 게 없고, 브라우저 생명주기만 "요청마다 새로 띄움"에서 "앱 시작 시
한 번 띄워서 재사용"으로 바뀌었다(자세한 이유는 `server/render.py` 상단 주석 참고).

원래 `engine-ai-prototype/`(2026-softstudio-project 저장소 밖, 이 저장소에는 없음) 폴더에
있던 참고용 기준선(`golden_catalog.json`, `bakeoff_results_run6_final.json`)은 이관하면서
**이 폴더(`parsing-engine/`) 바로 아래로 같이 옮겨왔다** — `tools/golden_regression_check.py`
가 이제 이 폴더 안에서만 실행돼도 회귀 검사를 할 수 있게 자기완결적으로 구성했다.

## 구성

```
golden_catalog.json                — 골든셋 36개 상품(12개 몰) 정답지
bakeoff_results_run6_final.json    — engine-ai-prototype 프로토타입 단계 기준선(run6)
server/
  main.py       — FastAPI 앱, POST /extract, GET /healthz, 브라우저 생명주기(lifespan)
  render.py     — Playwright 렌더링(async, 브라우저 재사용). 로직은 engine-ai-prototype과 동일
  providers.py  — Gemini 호출/재시도/스크린샷 폴백. engine-ai-prototype과 동일 + 재시도
                  횟수만 환경변수로 뺌
  prompts.py    — 시스템 프롬프트/few-shot/JSON 스키마. engine-ai-prototype과 완전히 동일
                  (문구를 바꾸지 않았음)
  compare.py    — 그라운딩 체크(응답에 포함) + 골든셋 비교(회귀 테스트용)
  cache.py      — RenderCache Protocol + 캐시 키 정규화 (실제 구현은 아직 없음, NoOpCache만)
  metrics.py    — 요청별 elapsed_ms/peak_rss_mb 측정
  config.py     — 전부 환경변수로 오버라이드 가능한 설정값
tools/
  golden_regression_check.py — 로컬 서버에 골든셋 36개를 던져서 run6 기준선과 비교
  concurrency_load_test.py   — 동시 요청 N건 부하 테스트(AWS Fargate 검증에 사용)
```

## 실행

```bash
cd server
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
playwright install chrome   # 또는 이미 설치된 크롬을 쓰려면 생략(폴백 있음)
cp .env.example .env        # GEMINI_API_KEY 채우기
uvicorn main:app --host 0.0.0.0 --port 8000
```

```bash
# 다른 터미널에서 회귀 테스트 (parsing-engine/tools에서 실행)
cd ../tools
python golden_regression_check.py \
  --golden-catalog ../golden_catalog.json \
  --baseline ../bakeoff_results_run6_final.json
```

## 하지 않은 것 (의도적으로 범위 밖에 둠)

- AWS 리소스 생성/배포, 실제 캐시 백엔드 구현, DB 연동, Flutter 앱 쪽 통합 — 전부 이 작업의
  범위가 아니다(보고서의 "다음에 결정이 필요한 것" 참고).
- 몰별 규칙 기반 폴백 — 이번 방향(AI 완전 대체)과 어긋나서 추가하지 않았다.
