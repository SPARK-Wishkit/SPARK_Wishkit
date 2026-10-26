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

**2026-10-24 갱신**: 앱의 WebView 추출기를 제거하고, 앱은 상품 URL 을 이 서버로만 읽는다(GraphQL
`extractProduct` → `parsing-proxy` Lambda → `POST /extract`). AppSync 30초 한도 때문에 배포 시
`EXTRACT_TIMEOUT_S=25`로 띄운다(`deploy/engine.sh`). 아래 문단은 그 전 상황 기록이다.

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
  providers.py  — Gemini 텍스트/스크린샷(비전) 호출 + 429 재시도. 호출 방식은
                  engine-ai-prototype과 동일(bakeoff용 Anthropic/OpenAI 함수는 서버에서 제거)
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

## 태그 사진으로 찾기 — `POST /identify-tag` (2026-10-22 추가)

`{image_base64, mime_type}`를 받아 태그의 품번으로 상품 상세 페이지를 찾는다(공식몰 우선, 없으면
국내 쇼핑몰). **가격은 읽지 않는다** — 앱이 돌려받은 URL을 기존 "URL로 담기" 경로로 읽는다.

1. 태그 읽기: Gemini 비전 + JSON 스키마(브랜드·품번·다른 코드들·바코드·상품명·색상·태그 가격).
   바코드는 검증 숫자가 안 맞으면 버린다(`tag_codes.py`).
2. 검색: Gemini + Google 검색 그라운딩(텍스트 응답을 직접 파싱 — 도구와 JSON 스키마를 같이
   쓰면 그라운딩 메타데이터가 비는 문제가 보고돼 있음)
3. 확인: 후보 페이지를 렌더링해서 **품번(또는 바코드)이 페이지에 실제로 있는지** 확인. 품번이
   있는데 페이지에 없으면 이름이 비슷해도 인정하지 않는다. 색상 코드를 뗀 기본 번호(`product_code_base`)도
   근거로 쓰고, 같은 수준의 후보끼리는 태그 가격이 페이지에 보이는 쪽(`tag_price_seen`)을 고른다.
4. 응답: `status`(found / not_found / not_a_tag), `tag`, `match`(url·host·source·verified_by)

⚠️ 앱 → AppSync → Lambda 경로는 AppSync가 30초에 끊는다. 그래서 `IDENTIFY_TIMEOUT_S` 기본값을
25초로 두고, 남은 시간이 모자라면 후보 확인을 덜 하고 not_found로 끝낸다.

정확도는 실제 태그 사진으로 잰다: `tools/tag_identify_check.py --photos ./photos`
(사용법은 파일 상단 참고. 품번 읽기 정확도와 페이지 찾기 정확도를 따로 센다.)

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
