# Tab S7 실페이지 대조 — 완료 (2026-08-20)

Draft PR #28. **머지하지 말 것.**

2026-08-18 카탈로그(50몰, 낫포유 2상품) 기준 Tab S7 WebView 추출 vs live 정답 대조가 **2026-08-20에 전부 끝났다.** 엔진 코드는 대조 중 수정하지 않았다.

---

## 최종 결과 요약

- **완료:** 50/50몰, 149/149 상품 슬롯
- **MATCH 3/3 (15몰):** 무신사, 29CM, FILA, 탑텐, 무인양품, 현대Hmall, 유니클로, 게스, 반스, 후아유, 아모멘토, 예일, 퀸잇, 브랜디, SSF샵
- **집계 파일:** `audit-logs/compare-progress.txt`, `audit-logs/compare-final-summary.json`
- **배치 로그:** `audit-logs/compare-batch-2026-08-20-*.log`

### 몰별 분류 (틀린 필드)

| 몰 | 1 | 2 | 3 |
|---|---|---|---|
| 11번가 | MATCH | IMAGE | PRICE_IMAGE |
| 무신사 | MATCH | MATCH | MATCH |
| W컨셉 | NAME_PRICE | NAME | NAME |
| 29CM | MATCH | MATCH | MATCH |
| FILA | MATCH | MATCH | MATCH |
| 하고 | IMAGE | IMAGE | IMAGE |
| 룩핀 | IMAGE | IMAGE | IMAGE |
| 탑텐 | MATCH | MATCH | MATCH |
| 무인양품 | MATCH | MATCH | MATCH |
| 현대Hmall | MATCH | MATCH | MATCH |
| 롯데온 | PRICE | PRICE | PRICE |
| 미쏘 | MATCH | PRICE | PRICE |
| 데일리쥬 | MATCH | MATCH | PRICE |
| 리 | PRICE | PRICE | PRICE |
| 필루미네이트 | PRICE | PRICE | PRICE |
| 어반스터프 | PRICE | PRICE | PRICE |
| 낫포유 | PRICE | PRICE | (2상품) |
| 인사일런스 | PRICE | PRICE | PRICE |
| 파브레가 | PRICE | PRICE | PRICE |
| 핫핑 | NAME | NAME | NAME |
| 유니클로 | MATCH | MATCH | MATCH |
| SSG | PRICE_IMAGE | PRICE_IMAGE | PRICE_IMAGE |
| 더현대Hi | PRICE | PRICE | PRICE |
| 에이블리 | NAME_PRICE_IMAGE | NAME_PRICE_IMAGE | NAME_PRICE_IMAGE |
| 지그재그 | PRICE | PRICE | MATCH |
| KREAM | PRICE | PRICE | PRICE |
| 게스 | MATCH | MATCH | MATCH |
| 반스 | MATCH | MATCH | MATCH |
| 커버낫 | PRICE | MATCH | MATCH |
| 코드그라피 | PRICE | PRICE | PRICE |
| 후아유 | MATCH | MATCH | MATCH |
| Aritzia | MATCH | PRICE | PRICE |
| 노이아고 | PRICE | PRICE | PRICE |
| 립합 | PRICE | PRICE | PRICE |
| 마하그리드 | PRICE | PRICE | PRICE |
| 비바스튜디오 | PRICE | PRICE | PRICE |
| 아모멘토 | MATCH | MATCH | MATCH |
| 앤더슨벨 | MATCH | NAME_PRICE_IMAGE | MATCH |
| 예일 | MATCH | MATCH | MATCH |
| 위드윤 | PRICE | MATCH | PRICE |
| 패션플러스 | PRICE_IMAGE | PRICE_IMAGE | PRICE_IMAGE |
| 프롬비기닝 | PRICE | PRICE | PRICE_IMAGE |
| 나이키 | PRICE | PRICE | MATCH |
| 올리브영 | PRICE | PRICE | MATCH |
| 퀸잇 | MATCH | MATCH | MATCH |
| 브랜디 | MATCH | MATCH | MATCH |
| CJ온스타일 | PRICE | PRICE | MATCH |
| 4910 | PRICE | PRICE | PRICE |
| SSF샵 | MATCH | MATCH | MATCH |
| 이랜드몰 | MATCH | IMAGE | MATCH |

분류 이름은 **맞은 필드가 아니라 틀린 필드**다. `MATCH` = 세 필드 모두 일치.

---

## 다음 단계 (엔진 패치 — 우선순위)

대조 숫자를 모두 모았으므로 아래부터 코드 수정 가능.

1. W컨셉 og:title → `[W CONCEPT]` 접두
2. Cafe24 `price_ambiguous` (코드그라피·노이아고·립합·위드윤·낫포유 등)
3. 에이블리 `loading_timeout`
4. 핫핑 이름 HTML 태그 제거
5. 하고·룩핀·SSG·패션플러스 대표 이미지 og 플레이스홀더
6. 더현대Hi·4910·패션플러스 **live 카탈로그** 정답 재확인
7. 앤더슨벨 2번 `not_product_page` URL/리다이렉트

---

## 참고 (환경·명령)

- 브랜치: `feat/webview-scraper-stabilize`
- 카탈로그: `flutter_app/integration_test/live_field_compare_catalog.dart`
- 러너: `flutter_app/integration_test/live_field_compare_test.dart`
- 기기: Tab S7 `R54RB01SMVB`, `--no-uninstall` 필수
- hang 완화: `tools/run_tab_s7_compare.py` (ADB 리셋, 12초 cooldown)
- 인수인계: `ENGINE_DEVELOPMENT_HANDOFF.md` §0.13

## 커밋에 넣지 말 것

- `flutter_app/.dart_tool/`, `build/`
- `tools/_*.py` 일회성 스크립트
- 대량 `audit-logs/live-*.json`, 로그인 쿠키, `.env`
