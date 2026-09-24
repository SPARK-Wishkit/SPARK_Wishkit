# PRICE 몰 2인 분담 핸드오프

인원: **2명** (팀원 1 + 기기 소유자 1)  
베이스: `feat/webview-scraper-stabilize`  
Draft PR: https://github.com/soft-studio-team/2026-softstudio-project/pull/28

## 역할 (딱 둘)

| 누구 | 역할 | 하는 일 |
|------|------|---------|
| **팀원** | PC 패치 | 맡은 몰만 프로브·엔진/카탈로그 수정·unit test·push → PR에 Tab 검증 요청 |
| **나 (S7 소유)** | 패치 + Tab | 나머지 몰 패치 + **두 사람 패치 전부** Tab 검증·머지·PR 코멘트 |

Tab S7(`R54RB01SMVB`)은 **나만** 돌린다. 팀원은 Tab/adb/`run_tab_s7_compare.py` 실행 금지.

## 몰 분담

### 팀원 — Cafe24 / 브랜드
브랜치: `fix/price-teammate-cafe24`  
몰: **코드그라피, 커버낫, 데일리쥬, 낫포유, 인사일런스, 핫핑(NAME)**

### 나 — SPA / 대형 + 전체 Tab
브랜치(패치용): `fix/price-owner-spa`  
몰(패치): **올리브영, 롯데온, 지그재그, KREAM, Aritzia, 11번가(IMAGE), 이랜드몰(IMAGE), 에이블리, SSG**  
추가 의무: 팀원 브랜치까지 pull 해서 Tab MATCH 확인 · **2026-08-21 두 브랜치 모두 `feat/webview-scraper-stabilize`에 병합 완료**

## 이미 끝난 것 (둘 다 건드리지 말 것)
미쏘·립합·마하그리드·프롬비기닝·리·필루미네이트·어반스터프·파브레가·비바·나이키·CJ·4910·더현대Hi·앤더슨벨·W컨셉 등 정가 MATCH 3 완료분.

## 공통 정책
- 정가(`product:price` / `product_price`) 우선. 회원가로 카탈로그 낮추지 말 것.
- `product_extract_js.dart`는 **자기 담당 몰 hostIs 블록만** 수정.
- `tools/_*.py`, bulk `audit-logs/` 커밋 금지.
- 에이블리·SSG Tab MATCH 3 완료 (itemView 차단 시 deal 경로 사용).

## 협업 흐름
1. 팀원이 패치 push → PR #28에 `Tab 검증 요청: [몰] / 브랜치 / 예상 정가`
2. 내가 그 브랜치 checkout → `run_tab_s7_compare.py`로 검증
3. MATCH 3 → 피처 브랜치 반영·CHANGELOG·코멘트 / 실패 → eng·live·failureReason 회신
4. 내 SPA 몰도 같은 방식으로 패치 후 내가 Tab까지 마침

---

## Cursor 프롬프트 (복붙용 · 2개만)

### 1) 팀원용 프롬프트

```
너는 wishlist WebView 추출 엔진 패치 담당(팀원)이다. 인원은 나+기기소유자 2명뿐이다.
Tab S7 실기기는 없다. PC 작업만 한다. Tab/adb/run_tab_s7_compare.py/integration_test 실기기는 실행하지 말 것.

베이스: feat/webview-scraper-stabilize
브랜치: fix/price-teammate-cafe24 (없으면 feat/webview-scraper-stabilize 에서 생성)
Draft PR: https://github.com/soft-studio-team/2026-softstudio-project/pull/28
문서: wishlist-appversion2/PRICE_SPLIT_HANDOFF.md

내 담당 몰만 한다:
- 코드그라피, 커버낫, 데일리쥬, 낫포유, 인사일런스, 핫핑(NAME)

하지 말 것:
- 올리브영, 롯데온, 지그재그, KREAM, Aritzia, 11번가, 이랜드몰
- 에이블리, SSG
- 이미 MATCH 완료된 몰

정책:
- 정가(product:price / product_price) 우선. 회원가로 카탈로그를 맞추지 말 것.
- product_extract_js.dart는 위 몰 hostIs 블록만 수정.

작업 루프:
1) 카탈로그 URL PC 프로브 → 원인 정리
2) product_extract_js.dart / live_field_compare_catalog.dart 패치
3) flutter test test/product_extract_js_sync_test.dart 통과
4) push 후 PR #28에 「Tab 검증 요청」 코멘트 (몰, 브랜치, 예상 정가, 변경 한줄)
5) 기기 소유자가 Tab 실패를 주면 패치만 고쳐서 다시 요청

참고: cafe24MetaList, verifiedCafe(covernat/code-graphy), dailyjou, not4u, insilence, hotping
응답은 한국어.
```

### 2) 나(기기 소유자)용 프롬프트

```
너는 wishlist WebView 패치+Tab 검증 담당이다. 인원은 팀원+나 2명뿐이다.
Tab S7(R54RB01SMVB)은 나만 쓴다.

베이스: feat/webview-scraper-stabilize
내 패치 브랜치: fix/price-owner-spa (없으면 생성)
팀원 브랜치: fix/price-teammate-cafe24
Draft PR: https://github.com/soft-studio-team/2026-softstudio-project/pull/28
문서: wishlist-appversion2/PRICE_SPLIT_HANDOFF.md

내 패치 몰:
- 올리브영, 롯데온, 지그재그, KREAM, Aritzia, 11번가(IMAGE), 이랜드몰(IMAGE)

추가 의무:
- PR #28의 「Tab 검증 요청」이 오면 팀원 브랜치를 checkout 해서 Tab 검증
- 내 패치 몰도 패치 후 내가 Tab까지 마침
- cwd: wishlist-appversion2, python tools/run_tab_s7_compare.py, --no-uninstall, MALLS에 대상 몰만
- MATCH 3면 피처 브랜치 반영·CHANGELOG·PR 코멘트
- 실패면 eng/live/failureReason을 PR에 남기고 팀원(또는 나)이 패치 수정

정책:
- 정가/조건 없는 판매가 우선. 쿠폰·회원·첫구매가로 맞추지 말 것.
- 팀원 몰(코드그라피·커버낫·데일리쥬·낫포유·인사일런스·핫핑) 엔진은 팀원 요청 없이 임의로 크게 바꾸지 말 것(Tab만 하거나, 명확한 핫픽스만).
- 에이블리·SSG MATCH 3 완료. hang 시 adb kill/start + force-stop.

응답은 한국어.
```
