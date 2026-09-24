# wishkit 파싱 엔진 개발 인수인계서

작성 기준일: 2026-08-16

작업 디렉터리: `C:\0.My_Project\17.SoftStudio\2026-softstudio-project\wishlist-appversion2`

Git 저장소: `C:\0.My_Project\17.SoftStudio\2026-softstudio-project`

작업 브랜치: `feat/webview-engine-handoff`

기준 원격 브랜치: `origin/main` (`69a5bf2`까지 확인 후 rebase)

이 문서는 새 대화에서 wishkit 엔진 개발을 즉시 이어가기 위한 기준 문서다. 아래의 "다음 대화 시작 프롬프트"와 함께 이 파일을 읽도록 지시하면 된다.

## 0.0 2026-08-21 현황 (읽기 시작점)

- **가격 엔진(50몰 live compare)**: Tab S7 MATCH 인증 완료. 지원/미지원 목록 → [`MALL_SUPPORT.md`](./MALL_SUPPORT.md)
- **브랜치**: `fix/price-owner-spa` + `fix/price-teammate-cafe24` → `feat/webview-scraper-stabilize`에 병합됨
- **남은 일**: PR #28 draft 해제·main 머지 준비, (선택) 50몰 전체 Tab 회귀
- **의도적 미지원**: Gap·LF·NUGU·SHEIN·네이버(기권), 쿠팡(차단). 리바이스 대기 늘리지 않음

## 0. 2026-08-16 후속 작업 결과

기준 브랜치: `feat/webview-engine-handoff` (`aaac9ca`, PR #27 미병합)

구현 브랜치: `feat/webview-scraper-stabilize`

`webview_scraper.dart` 안정화는 코드와 단위 테스트까지 반영했다. Android 상품 추출 재감사는 통과로 보지 않는다.

구현한 동작:

- 마지막 `onLoadStart` / `onLoadStop` / `onUpdateVisitedHistory` 이후 600ms 안정화
- `evaluateJavascript` 호출별 4초 timeout, timeout 후 같은 controller에 중첩 호출하지 않음
- 명시적 `blocked=true`는 즉시 `access_blocked`로 종료, origin warm-up/reload 없음
- 빈 결과에만 같은 URL 1회 reload. 차단·품절·가격 충돌·미지원 통화는 재시도하지 않음
- URL·adapter·price·originalPrice·옵션 범위 fingerprint가 두 번 연속 같으면 확정
- 실패 이유: `loading_timeout`, `script_timeout`, `access_blocked`, `network_error`, `not_product_page`, `price_ambiguous`, `unsupported_currency`
- `WebViewExtractLoop` + `ExtractClock`으로 폴링/안정화 단위 테스트

검증:

- `flutter test test/product_extract_js_sync_test.dart test/webview_scraper_result_test.dart` → 20 passed
- `flutter analyze` 대상 파일 → 0 issues
- SuperDisplay 프로세스는 없었고 SDK ADB 1.0.41만 사용. Pixel 10 에뮬레이터 `emulator-5554` / Android 17 / API 37
- 첫 설치는 `adb.exe: cannot connect to daemon at tcp:5037`로 실패. 재시도 후 러너는 완주
- `WEBVIEW_AUDIT_ONLY=14,22,24,46,49,53,55`: 7/7 `NO_RESULT` + `loading_timeout`, 상품명/이미지/가격 없음. 가격 통과로 보고하면 안 됨
- `WEBVIEW_AUDIT_START=0 END=3`: 쿠팡 `NO_RESULT`, 네이버는 러너가 `EXPECTED_ABSTAIN`으로 집계했지만 실제로는 같은 `loading_timeout`, 11번가는 hang 없이 `loading_timeout`. 후속 오염은 없었음
- Headless WebView의 `onLoadStop`/`onReceivedError`가 발생하지 않고 `isRunning()`이 곧 false가 되어 추출 JS를 실행하지 못했다. 4~64 전체 감사는 같은 인프라 실패를 반복할 뿐이라 실행하지 않았다
- 실물 기기 앱/데이터 삭제 없음. 로그인·결제·장바구니 변경 없음

다음 우선순위는 SuperDisplay를 완전히 종료한 뒤, 위젯 호스트 경로로 7개(`14,22,24,46,49,53,55`)와 1~3 / 4~64 분할 감사를 다시 실행하는 것이다. 그 전에는 64개 가격 재감사를 통과로 보고하면 안 된다.

**2026-08-20 Tab S7 50몰 실페이지 대조 완료.** 엔진 코드 변경 없음. 아래 §0.13·`TAB_S7_LIVE_COMPARE_CONTINUATION.md`·`audit-logs/compare-final-summary.json` 참고. 패치는 대조 숫자 기준으로 다음 단계.

## 0.13 2026-08-20 Tab S7 실페이지 대조 완료

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28, Draft — **머지 금지**)

기기: Galaxy Tab S7 `SM-T870` / `R54RB01SMVB` / Android 13. ADB `C:\Users\tingo\AppData\Local\Android\sdk\platform-tools\adb.exe`. `--no-uninstall`. SuperDisplay 없음.

분류: 라벨은 **틀린 필드**다. `MATCH` = 이름·가격·사진 모두 일치. `PRICE` = 이름·사진 맞고 가격만 불일치.

**결과:** 카탈로그 50몰(낫포유 2상품) 전부 대조 완료. 상품 슬롯 149/149.

- **MATCH 전부(15몰):** 무신사, 29CM, FILA, 탑텐, 무인양품, 현대Hmall, 유니클로, 게스, 반스, 후아유, 아모멘토, 예일, 퀸잇, 브랜디, SSF샵
- **가격 이슈 다수:** Cafe24 계열 `price_ambiguous`(코드그라피·노이아고·립합·위드윤 등), ~90% 회원가(리·필루미네이트·어반스터프·파브레가·비바스튜디오), 나이키/CJ온스타일 엔진 정가 vs live 할인가
- **이름:** W컨셉(`[W CONCEPT]`), 핫핑 HTML 태그
- **이미지:** 하고·룩핀 og 플레이스홀더, SSG·패션플러스(live `og_200x200.jpg` 의심), 이랜드몰 2번
- **복합:** 에이블리 3(`loading_timeout`), 앤더슨벨 2번 `not_product_page`(홈 리다이렉트)
- **live 재확인 후보:** 더현대Hi, 4910(1000/1690원), 패션플러스 og 이미지

몰별 상세: `audit-logs/compare-progress.txt`, JSON `audit-logs/compare-final-summary.json`. 2026-08-20 배치 로그 `compare-batch-2026-08-20-*.log`.

운영: 1~2몰씩, hang 시 ADB kill-server + 화면 깨우기 + force-stop. `tools/run_tab_s7_compare.py`(몰 간 12초 cooldown). 검사 후 uninstall 금지, 종료 후 `adb install -r`로 debug APK 복구.

하지 말 것: 리바이스 대기 늘리기, 관리 몰 범용 가격 우회, **대조 완료 전** 엔진 패치(이제 패치 단계), PR 머지.

다음: §0.13. **더현대Hi MATCH 3**, **4910 MATCH 3**(가격이 SSR `__NEXT_DATA__`에만 있어 `innerHTML` 검증으로 수정). 남음: 에이블리 로드, SSG, 회원가 정책.

## 0.12 2026-08-18 신규 3상품 정답지 + 엔진 대조

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

50몰 새 상품 페이지에서 이름·화면 판매가·사진을 읽어 카탈로그를 채웠다. 카탈로그를 엔진 JS로 채우지 않는다. `generate_live_catalog.py`는 JSON을 읽고 W컨셉 3개를 덮어쓴 뒤 JSON 전체를 다시 쓴다.

정답 3개 49몰. 낫포유 2(hang URL 290 제외). 퀸잇 3: 감사 URL `421b849e…`와 검색 결과에서 연 상품 페이지. 판매가는 `product.finalPrice`(첫구매·최대쿠폰 `maximumBenefitCouponAppliedFinalPrice` 제외).

브라우저로 채운 예: Aritzia는 `[data-testid=product-list-price-text]`의 `₩211,500` (무료배송 `₩200000` 금지). 에이블리 3번째는 쿠폰적용가 17120이 아니라 즉시할인 판매가 24450. 유니클로는 목록가 19900·chip 이미지가 아니라 페이지 판매가 49900·`kr/imagesgoods/…_3x4.jpg`.

탭 S7 `--no-uninstall` 신규 정답 대조 (2026-08-18 완료):

- MATCH 3: 무신사, 29CM, 게스, 후아유, 예일, FILA, 아모멘토, 앤더슨벨, 반스, SSF샵, 유니클로, 현대Hmall, 퀸잇, 브랜디, 탑텐, 무인양품
- MATCH 2: 위드윤, 커버낫, 데일리쥬, 11번가, 롯데온, 이랜드몰
- MATCH 1: Aritzia, 지그재그, CJ온스타일, 미쏘, 나이키, 올리브영
- IMAGE 3: 룩핀 이름·가격 일치, 엔진 이미지 `og_tag_lookpin_web.jpg`
- IMAGE 1: 이랜드몰 2(엔진·live 이미지 날짜 경로 불일치, 이름·가격 일치)
- PRICE·엔진 맞음·live 카탈로그 오류(재수집 후 MATCH): 탑텐 3, 무인양품 3
- PRICE·엔진 이슈: 코드그라피 3(`price_ambiguous`), 프롬비기닝 3(~20% 낮음), Aritzia 2(`price_ambiguous`), 올리브영 2(`price_ambiguous`), 노이아고 3(엔진 null·`price_ambiguous`)
- PRICE_IMAGE: SSG 3(엔진 null·`price_ambiguous`, 이미지 stem 일치·`_1200` vs `_250` URL)
- `loading_timeout`: 에이블리 3
- W컨셉 단독: 1 NAME_PRICE(`[W CONCEPT]`, 가격 39000 vs 29120), 2·3 NAME만(`[W CONCEPT]`, 가격·사진 일치)
- 정답 품질 주의: 탑텐·무인양품 live 가격·이미지 재수집 필요, 패션플러스 live `og_200x200.jpg`, 더현대Hi·4910 live 가격 이상
- 검사 후 debug APK `-r` 복구

다음: W컨셉 og:title, 올리브영·노이아고·SSG 가격 추출, 에이블리 `loading_timeout`. 탑텐·무인양품 live 정답은 브라우저로 재수집 완료. 리바이스 대기는 늘리지 않음.

## 0.11 2026-08-18 탭 S7 50몰 전부 대조

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

`SM-T870` / `R54RB01SMVB`에서 자동 채움 50몰을 배치로 모두 열었다. `--no-uninstall`. 검사 후 debug APK `-r`.

MATCH: 무신사 3, 29CM 3(단독 세션), 반스 3, 나이키 1, 후아유 3, 게스 3, 핫핑 3, 낫포유 2, 예일 3, 데일리쥬 2, 커버낫 2, 필루미네이트 1, 인사일런스 1, 코드그라피 1, 노이아고 1, 립합 1, 아모멘토 1, 앤더슨벨 1, 위드윤 2.

가격만 불일치(이름·사진 맞음): 미쏘, 리(79200 vs 99000), 어반스터프(약 10% 낮음), 파브레가(39600 vs 44000), 마하그리드(65400 vs 109000), 프롬비기닝(약 20% 낮음), 일부 `price_ambiguous`.

W컨셉 1: 이름 `[W CONCEPT]`, 가격·사진 일치. 2·3 `script_timeout`. 노이아고 2140은 extract가 끝나지 않아 hang. SSG 두 번째는 `access_blocked`.

live 없는 몰은 ENGINE_ONLY로 이름·가격·사진을 남겼다.

다음: W컨셉 og:title, 카페24 sale_price vs 화면가, 노이아고 hang. 리바이스 대기는 늘리지 않음.

## 0.10 2026-08-17 WebView vs 실페이지 이름·가격·사진 대조

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

자동 채움 PASS 50몰을 대상으로 WebView 추출 값과 실제 상품 페이지 확인 값을 비교한다. 이전 64몰 감사는 양수 가격 유무만 봤고, 이번 검사는 이름·가격·사진이다.

비교 규칙 (`lib/services/live_field_compare.dart`):

- 이름: 완전 일치, 한쪽이 다른 쪽을 포함, 브랜드를 뺀 뒤 포함, live 토큰이 모두 engine에 있으면 통과. 엔진 이름에 `[트위]`·`VANS` 같은 부가 정보가 붙는 경우를 허용한다. 추출 JS에서 브랜드를 지우지는 않는다.
- 가격: 엔진 판매가 == 실페이지 판매가. 첫구매·카드·앱 쿠폰은 정답이 아니다. 무신사 6152461은 화면에 21,280이 보여도 `goodsPrice.salePrice` 30400. 29CM 3503849는 첫구매가 177,510이 아니라 `item.sellPrice` 206400.
- 사진: 쿼리 제거 canonical URL, 파일 stem 포함.

러너: `flutter test integration_test/live_field_compare_test.dart -d R3CY10LF2HE --no-uninstall --dart-define=LIVE_COMPARE_MALLS=무신사,반스,나이키`

갤럭시 탭 S7 (`SM-T870` / `R54RB01SMVB` / Android 13)에서 대조를 실행했다. JS probe=`2`. `--no-uninstall`. 검사 후 debug APK `-r` 복구.

MATCH: 무신사 3, 반스 3, 나이키 1(엔진명에 브랜드·카테고리 부가), 후아유 3, 커버낫 2.

불일치/실패:

- W컨셉 307615241: 가격 19900·사진 일치, 이름 `[W CONCEPT]`
- W컨셉 이후 같은 세션의 29CM/미쏘/게스/커버낫/후아유: `script_timeout`. 새 세션에서 미쏘·커버낫·후아유는 추출됨
- 미쏘: 이름·사진 일치, 가격은 `product:sale_price:amount`(12470, 49950) vs 화면/og 49900·99900
- 커버낫 8581: 이름·사진 일치, `price_ambiguous`

앱 uninstall 없음. 리바이스 대기는 늘리지 않음.

50몰 전부 대조는 0.11.

## 0.9 2026-08-17 파이썬 파싱 엔진 폴더 제거

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

`wishlist-appversion2/parsing-engine/`을 삭제했다. 공유 담기와 상품 추출은 WebView만 사용한다. 파이썬 폴백은 없다.

가격 규칙 기준: `flutter_app/lib/services/product_extract_js.dart`. 스키마 필드는 `ParsedProductInfo` / `OnDeviceExtract`.

다음: 리바이스 timeout은 고정 대기를 늘리지 않는다. 가격이 비는 관리 몰 전용 규칙은 필요할 때만.

## 0.8 2026-08-17 앱의 파이썬 서버 연결 제거

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

공유 담기 스모크(0.7) 이후, 앱이 파이썬 서버를 부를 수 있는 남은 코드를 지웠다. `parsing-engine/` 폴더는 0.9에서 삭제했다.

- `lib/config.dart` (`ENGINE_BASE_URL` / `10.0.2.2:8000`) 삭제
- `ParsedProductInfo`의 `/parse`·`/api/scrap` JSON 팩토리 삭제
- `engineUsed` 기본값 false
- 직접 쓰이지 않던 `http` 패키지 제거
- 단위 테스트 43 passed, 대상 analyze 0 issues

다음: 파이썬 폴더 제거는 0.9. 리바이스 timeout은 고정 대기를 늘리지 않는다.

## 0.7 2026-08-17 갤럭시 공유 담기 스모크

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

공유 담기 화면이 쓰는 `ParsingBridge`를 실물 Galaxy WebView 호스트로 확인했다. 위시리스트/Firebase에 저장하지 않았다.

환경:

- `flutter test integration_test/share_intake_smoke_test.dart -d R3CY10LF2HE --no-uninstall`
- JS probe=`2`, SuperDisplay Stopped, SDK ADB 1.0.41
- 로그인·결제·장바구니 변경 없음. 앱 uninstall 없음.

결과:

| 입력 | 분류 | 이름 | 가격 | engineUsed |
|---|---|---|---:|---|
| 반스 공유 텍스트 | 자동 채움 | 올드스쿨 | 57000 | false |
| ZARA URL | 수동 가격 | 플리츠 쇼트 트렌치 코트 | 0 (`price_ambiguous`) | false |
| 쿠팡 URL | 불안정 | 통과 실행은 Access Denied | 0 (`access_blocked`) | false |

쿠팡은 `managedDomains`에 없다. 1차 실행에서 페이지가 열려 11990/이미지가 나왔고, 통과 실행에서는 차단 화면이었다. 우회 코드를 넣은 것이 아니며 안정 PASS로 세지 않는다.

원본: `wishlist-appversion2/share_intake_smoke_2026-08-17.json`.

검사 후 `flutter build apk --debug` + `adb install -r`. 패키지 `com.softstudio.wishlist` 유지.

다음: 앱의 파이썬 연결 제거는 0.8. 리바이스 timeout은 고정 대기를 늘리지 않는다.

## 0.6 2026-08-17 iOS blank 리셋 재확인

구현 브랜치: `feat/webview-scraper-stabilize` (`eafa6b3`, PR #28)

64개 전체가 아니다. blank 리셋 이후 연속 추출 오염과 Android와 갈리던 4몰만 봤다.

환경:

- 단위 테스트 4파일 통과 (`product_extract_js_sync` / `webview_scraper_result` / `parsing_bridge` / `share_input`)
- JS probe=`2.0`, `--no-uninstall`
- 실물 iPhone `지으닝`(iPhone 16, iOS 26.6, wireless `00008140-001202993CEB001C`)은 `available (paired)`였으나 `flutter test`가 wireless tether에서 앱을 시작하지 못함 (`Cannot start app on wirelessly tethered iOS device`)
- 사용 기기: iPhone 17 Pro 시뮬레이터 `53D6E81D-B9AC-48B0-8175-7F12FECF1041` / iOS 26.5
- 파이썬 서버 미사용. 로그인·결제·장바구니 변경 없음. 감사 러너는 `--no-uninstall`

오염 3쌍 — 모두 없음. `finalUrl`·상품명·adapter가 요청 몰과 같다.

| 순서 | 몰 | 분류 | 가격 | finalUrl 호스트 |
|---|---|---|---:|---|
| 56→57 | 퀸잇 → 브랜디 | PASS → PASS | 32900 → 34500 | queenit.kr → brandi.co.kr |
| 10→11 | 탑텐 → 무인양품 | PASS → PASS | 19900 → 9900 | topten10.goodwearmall.com → mujikorea.co.kr |
| 33→34 | 코드그라피 → 후아유 | PASS → PASS | 70300 → 19900 | code-graphy.com → whoau.com |

이전 iOS 시뮬레이터 64(PR #31)에서는 무인양품←탑텐, 후아유←코드그라피, 퀸잇 DOM이 브랜디 등으로 샜다. 이번 코드는 추출마다 `about:blank` `onLoadStop`을 기다린다. 연속 실행에서 그 오염은 재현되지 않았다. 퀸잇 판매가는 이전 29900에서 32900으로 바뀌었고, 전용 어댑터 PASS는 유지.

Android와 갈리던 4몰:

| 몰 | iOS 재확인 | failureReason | Android 최신 | 이전 iOS 64 |
|---|---|---|---|---|
| SSG | BLOCKED. 이름 「안전한 서비스 이용을 위해접속이 잠시 제한되었습니다」. finalUrl `https://www.ssg.com/item/itemView.ssg?itemId=1000571660298` | `access_blocked` | PASS | BLOCKED |
| 반스 | PASS 올드스쿨 57000, `source.price=site-adapter`. finalUrl `https://www.vans.co.kr/PRODUCT/VN000D6WBOM` | null | PASS 올드스쿨 57000 | PASS 올드스쿨 57000 |
| Aritzia | PARTIAL_NO_PRICE. 이름 `www.aritzia.com`, 이미지/가격 null. finalUrl 상품 URL 유지 | `price_ambiguous` | PASS 88900 | PARTIAL_NO_PRICE(이름·이미지 있음, 가격 null) |
| 마리떼 | PASS 49000, `source.price=site-adapter`. finalUrl `https://marithe-official.com/product/detail.html?product_no=8883` | null | PARTIAL_NO_PRICE | PASS 49000 |

SSG 차단은 우회하지 않는다. Aritzia 전용 규칙 실패에 범용 JSON-LD/OG/DOM 가격을 넣지 않았다. 마리떼 iOS 전용 규칙은 가격이 나와 PASS로 적는다.

공유 담기 UI는 이번 재확인에서 돌리지 않았다. 단위 테스트만 통과. 원본 JSON: `wishlist-appversion2/ios_webview_recheck_2026-08-17.json`. PR #31 64몰 문서는 덮어쓰지 않음.

검사 후 `flutter install -d`로 일반 Debug를 시뮬레이터에 다시 넣었다. 이 명령이 시뮬레이터의 기존 앱을 지운 뒤 설치했다. 실기기 앱/데이터는 건드리지 않았다.

다음: 공유 담기 스모크는 0.7. 파이썬 엔진 폴더 정리는 앱 경로가 안정된 뒤에 한다. 리바이스 timeout은 고정 대기를 늘리지 않는다. Aritzia iOS 이름/이미지 품질은 이전 64보다 나빴으나 가격 우회로 고치지 않는다.

## 0.5 2026-08-17 공유 담기 WebView 전용

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

- 공유 담기는 파이썬 서버를 호출하지 않는다.
- WebView가 가격을 못 내도 이름·이미지·URL을 남기고 가격은 수동 입력한다.
- 저장 시 상품명과 양수 가격이 필요하다.

다음: 공유 담기 스모크는 0.7. 파이썬 엔진 폴더 정리는 앱 경로가 안정된 뒤에 한다. 리바이스 timeout은 고정 대기를 늘리지 않는다.

## 0.4 2026-08-17 blank 리셋·남은 몰 규칙

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

구현:

- 추출마다 `about:blank` `onLoadStop`을 기다린 뒤에만 대상 URL을 연다. 리셋 중 콜백·blank URL·다른 호스트 결과는 버린다.
- 반스 상품명은 `recopick:title` 우선.
- Hmall `itemPtc`/`slitmCd`, 이랜드 `/i/item`/`itemNo`, 나이키 `/t/`를 상품 페이지로 분류.
- 이랜드 전용 가격은 `s_price`(판매가). 쿠폰 `final_price`는 사용하지 않음.
- 품절/단종 표본 교체: Hmall `2060464676`, 나이키 `IH1698-100`, 이랜드 `2607498077`.

검증:

- `flutter test test/product_extract_js_sync_test.dart test/webview_scraper_result_test.dart` → 25 passed
- 대상 `flutter analyze` → 0 issues
- SuperDisplay Stopped, `--no-uninstall`, SDK ADB 1.0.41. JS probe=`2`.
- 실기기 5몰 `WEBVIEW_AUDIT_ONLY=12,30,31,54,64`: 현대Hmall PASS 42900, 반스 PASS 올드스쿨 57000, 나이키 PASS 134100, 이랜드몰 PASS 55600. 리바이스 `NO_RESULT`/`loading_timeout` 27.4초. 고정 대기는 늘리지 않음.
- 검사 후 일반 앱을 `flutter build apk --debug` + `adb install -r`로 복구한다.

다음: 공유 담기 WebView 전용은 0.5. 리바이스 timeout은 고정 대기를 늘리지 않는다.

## 0.3 2026-08-16 실기기 64개 분할 감사

실물 Galaxy에서 1~64를 나눠 완주했다. SuperDisplay는 끈 상태, `--no-uninstall`.

- PASS 46
- EXPECTED_ABSTAIN 5: 네이버 쇼핑, Gap, LF몰, NUGU, SHEIN
- BLOCKED 2: 쿠팡, H&M
- PARTIAL_MEDIA 1: 반스(가격·이미지 있음, 이름 없음. `recopick:title` 후보는 넣었으나 재감사 전)
- NO_RESULT 1: 리바이스 `loading_timeout`
- PARTIAL_NO_PRICE 9: 현대Hmall, 마리떼, 오호라, 육육걸즈, 파르티멘토, Reformation, 나이키(`not_product_page`), ZARA, 이랜드몰(`not_product_page`)

다음: 공유 담기 WebView 전용은 0.5. 리바이스 timeout은 고정 대기를 늘리지 않는다.
검사 후 일반 앱을 `-r`로 복구했다.
iOS 작업자용 시작 프롬프트: `wishlist-appversion2/IOS_WEBVIEW_AUDIT_PROMPT.md`

## 0.2 2026-08-16 실기기 생성·로드·JS 복구

구현 브랜치: `feat/webview-scraper-stabilize` (PR #28)

확인된 것:

- 위젯 트리 `InAppWebView`를 `about:blank`로 항상 마운트하면 실물 Galaxy에서 `onWebViewCreated`와 `evaluateJavascript('1+1')=2`가 된다.
- 7개와 1~37은 실기기에서 페이지 내용을 읽었다. 가격 PASS로 볼 수 있는 곳은 전용 어댑터 또는 비관리 몰(11번가)에서 양수 가격이 나온 경우다.
- 오호라·파르티멘토·Reformation은 관리 몰이라 전용 규칙 실패 시 가격을 비웠다(`price_ambiguous`).
- 11번가는 hang 없이 15.6초에 끝났고 다음 건을 오염시키지 않았다.
- 반스는 가격/이미지는 되고 이름이 비었다. `recopick:title`을 이름 후보로 넣었다(재감사 전).
- 추출 사이에 `about:blank`로 비우지 않으면 에뮬레이터에서 이전 상품 DOM이 다음 몰 결과로 새어 나왔다. 호스트에 blank reset을 추가했다.

미완:

- 실기기 38~64(노이아고에서 러너 중단). 이후 실기기 재실행은 준비 단계에서 isolate 종료.
- iOS 동일 URL: 이 Windows 호스트에 iOS 기기/시뮬레이터 없음.
- 현대Hmall·리바이스·나이키·이랜드몰 규칙 재검증, 실패 UX, Python 폴백 결정은 다음.
- 실기기 감사는 반드시 `flutter test ... --no-uninstall`와 `adb install -r`만 사용한다. 기본 `flutter test`는 종료 시 패키지를 지운다.

SuperDisplay는 켜지 않는다.

## 0.1 2026-08-16 WebView 호스트 복구

Headless WebView는 Activity `android.R.id.content`의 첫 자식이 없으면 뷰 계층에 붙지 않는다. 감사 러너는 앱 위젯을 pump하지 않아 이 경로가 깨졌다.

대응:

- `WebViewExtractHost`: 360×640, opacity 0.01 `InAppWebView`를 트리에 붙임
- `WishlistApp`의 `MaterialApp.builder`와 감사 러너가 호스트를 pump
- `WebViewScraper.extract`는 호스트가 있으면 그 경로를 사용
- 단위 테스트 21개, analyze 0 issues

Android 재감사는 SuperDisplay ADB 40이 SDK ADB 41 서버를 다시 교체해 streamed install이 두 번 실패했다. 실물 `SM-S938N`이 연결되어 있었으나 앱/데이터는 삭제하지 않았다. 7개와 64개는 이번에도 Android 미검증이다.

## 1. 현재 결론

- Python 파싱 엔진과 Flutter WebView 추출기는 서로 다른 실행 경로다.
- Python 엔진은 서버에서 HTTP/내부 데이터 규칙으로 동작하며, WebView 추출기는 Android/iOS 앱 안에서 렌더링된 페이지를 읽는다.
- 현재 서버를 끈 Android WebView 단독 64개 대표 URL 감사에서 완전 PASS가 확인된 곳은 43개다.
- 반스는 가격과 이미지는 추출했으나 상품명이 누락되어 `PARTIAL_MEDIA` 1개다.
- 의도적으로 가격을 비우는 곳은 네이버 쇼핑, Gap, LF몰, NUGU, SHEIN 5개다.
- 명시적 차단은 쿠팡과 H&M이었으며 SSG·올리브영도 실제로는 한국어 접근 제한 화면이다. 현재 코드에는 이 두 한국어 차단 문구 감지가 추가되어 있다.
- 현대Hmall·리바이스·나이키·이랜드몰은 Android 실행에서 완전 결과가 없었고 11번가는 WebView timeout이었다.
- WebView만으로 100% 자동 추출은 현실적으로 어렵다. 목표 구조는 WebView 우선, 실패 시 URL·상품명·이미지 저장과 가격 수동 입력, 필요할 때만 Python/API 폴백이다.

## 2. 이번 작업에서 이미 반영한 변경

핵심 파일: `flutter_app/lib/services/product_extract_js.dart`

- 대표 이미지 URL 정규화
  - `https:https://` 중복 스킴 교정
  - `&amp;` 디코딩
  - 상대경로를 상품 URL 기준 절대경로로 변환
  - HTTPS 상품 페이지의 HTTP 이미지를 HTTPS로 우선 변환
- ZARA의 검증되지 않은 `ld.price * 100` provisional 후처리 제거
  - ZARA 전용 규칙이 성립하지 않으면 관리 도메인 원칙대로 가격을 비운다.
- 룩핀
  - 페이지 전체의 `품절` 문구를 보던 오류 제거
  - 주상품의 활성 `장바구니 담기/구매하기`와 비활성 품절 버튼을 확인
- 낫포유
  - Product JSON-LD에 availability가 없더라도 판매 옵션, 표시 판매가, `product_price`, Product offer가 모두 일치할 때만 medium confidence로 확정
- 미쏘
  - 현재 구매 버튼 문구 `구매하기` 반영
- 핫핑
  - `product:retailer_item_id`, KRW 메타 판매가, `product_price`, Product live offer를 교차 검증
  - 대표 상품 `29570`은 옵션에 따라 24,800~25,800원이므로 option-dependent로 반환
- 파르티멘토
  - JSON-LD 상품명의 `_`와 화면 공백 차이를 정규화
- 오호라
  - 추천/숨김 영역의 `재입고 알림` 때문에 정상 상품까지 차단하던 전역 검사를 제거
  - 화면에 실제로 보이는 주상품 `장바구니/바로 구매` 동작을 확인
- 접근 제한 감지
  - `접속이 잠시 제한되었습니다`
  - `잠시만 기다려 주세요`

관련 테스트: `flutter_app/test/product_extract_js_sync_test.dart`

- 대상 단위 테스트 7개 통과
- 관련 Flutter analyze 0 issues

## 3. 현재 작업 트리 상태

이 후속 작업은 `feat/webview-scraper-stabilize`에서 진행한다. 기존 `feat/webview-engine-handoff`의 커밋된 변경은 그대로 두고, WebView 안정화 파일만 추가/수정한다.

`git reset --hard`, `git checkout --`, `git clean`을 사용하지 않는다. 기존 사용자 변경을 되돌리지 않는다.

`flutter_app/android/local.properties`와 Flutter 전역 Android SDK 설정은 원래 SDK인 `C:\Users\tingo\AppData\Local\Android\sdk`로 복구했다. ADB 우회를 위해 만들었던 임시 SDK/프록시 디렉터리도 삭제했다.

## 4. Android 전체 감사 결과

환경:

- Pixel 10 에뮬레이터
- Android 17 / API 37
- Python 서버 미사용
- 로그인·결제·장바구니 변경 없음

64개 재감사 집계:

| 분류 | 수 | 의미 |
|---|---:|---|
| PASS | 43 | 상품명·이미지·확정 가격 반환 |
| PARTIAL_MEDIA | 1 | 반스: 가격·이미지 정상, 상품명 누락 |
| EXPECTED_ABSTAIN | 5 | 네이버, Gap, LF몰, NUGU, SHEIN |
| PARTIAL_NO_PRICE | 8 | 당시 전용 규칙 미통과 또는 접근 제한 |
| NO_RESULT | 4 | 현대Hmall, 리바이스, 나이키, 이랜드몰 |
| BLOCKED | 2 | 쿠팡, H&M |
| TIMEOUT | 1 | 11번가 |

이 실행에서 새 표본으로 정상 통과한 주요 항목:

- 룩핀 `3083865`: 28,900원 / 정가 54,900원
- 무인양품 `1005531`: 9,900원
- 리 `14252`: 79,200원 / 정가 99,000원
- 낫포유 `261`: 15,900원 / 소비자가 17,900원
- 인사일런스 `7481`: 59,000원
- 게스 `45471`: 39,000원 / 정가 49,000원
- Aritzia `133550?color=35023`: 88,900원
- ZARA `05063701`: 상품명·이미지만 반환하고 검증되지 않은 가격은 안전하게 제거

## 5. Android 최종 재검증이 남은 7개

2026-08-16 후속 실행은 러너만 완주했고 상품 추출은 전부 `loading_timeout`이었다. 아래 예상 결과는 여전히 Android 미검증이다.

감사 러너는 `WEBVIEW_AUDIT_ONLY`로 1-based 인덱스를 선택할 수 있게 되어 있다.

```text
14 미쏘
22 핫핑
24 SSG
46 오호라
49 파르티멘토
53 Reformation
55 올리브영
```

현재 대표 URL:

- 미쏘: `https://mixxo.com/product/detail.html?product_no=12455`
- 핫핑: `https://hotping.co.kr/product/detail.html?product_no=29570`
- SSG: `https://www.ssg.com/item/itemView.ssg?itemId=1000571660298`
- 오호라: `https://ohora.kr/product/detail.html?product_no=2275`
- 파르티멘토: `https://partimento.com/product/detail.html?product_no=16516`
- Reformation: `https://www.thereformation.com/products/delia-dress/1317591.html`
- 올리브영: `https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000260600`

예상 결과는 미쏘·핫핑·오호라·파르티멘토·Reformation의 가격 정상 추출, SSG·올리브영의 `BLOCKED` 분류다. 그러나 이 예상은 수정 후 Android에서 아직 검증되지 않았으므로 통과로 보고하면 안 된다.

## 6. WebView 안정화 작업 상태

위젯 호스트 경로는 코드에 반영했다. Android 재감사는 SuperDisplay ADB 40/41 충돌로 설치가 끊겨 미검증이다.

남아 있는 런타임 문제:

- SuperDisplay가 ADB server 40을 다시 띄워 SDK client 41과 충돌한다. 사용자가 SuperDisplay를 완전히 종료하기 전에는 에뮬레이터 설치 스트림이 끊긴다
- 가짜 SDK/ADB 프록시는 만들지 않는다
- 실물 기기 앱 제거·데이터 초기화는 하지 않는다
- 호스트 경로의 7개/64개 가격 재감사는 아직 실행하지 못했으므로 통과로 보고하면 안 된다

## 7. ADB 충돌

PC의 SuperDisplay 서비스가 ADB server version 40을 자동으로 실행하고 Android SDK의 ADB client/server version 41과 충돌한다.

대표 오류:

```text
adb server version (40) doesn't match this client (41)
error: protocol fault / connection reset
```

이 때문에 마지막 Android 7건 설치 스트림이 끊겼다. 실물 Galaxy 앱이나 사용자 데이터는 삭제하지 않았다. 에뮬레이터 테스트 앱만 Flutter 재설치 과정에서 제거됐다.

다음 실행 전 권장 조치:

- 사용자가 SuperDisplay를 완전히 종료하거나 관리자 권한으로 해당 서비스를 일시 중지
- SDK ADB만 실행되는지 `adb version`, `adb devices -l` 확인
- 실물 기기 대신 Pixel 10 에뮬레이터를 사용
- 테스트 종료 후 SuperDisplay가 필요하면 다시 시작

서비스 중지 권한이 없다면 임시 ADB 프록시/가짜 SDK를 다시 만들지 말고 사용자가 직접 SuperDisplay를 종료하도록 안내하는 편이 안전하다.

## 8. 테스트 명령

Flutter 작업 디렉터리:

```powershell
cd C:\0.My_Project\17.SoftStudio\2026-softstudio-project\wishlist-appversion2\flutter_app
```

단위 테스트와 정적 분석:

```powershell
flutter test test/product_extract_js_sync_test.dart test/webview_scraper_result_test.dart
flutter analyze lib/services/product_extract_js.dart lib/services/webview_scraper.dart integration_test/webview_all_malls_audit_test.dart test/product_extract_js_sync_test.dart
```

수정 대상 7개만 실행:

```powershell
flutter test integration_test/webview_all_malls_audit_test.dart -d emulator-5556 --dart-define=WEBVIEW_AUDIT_ONLY=14,22,24,46,49,53,55
```

전체 감사는 11번가의 네이티브 WebView hang이 후속 테스트를 오염시킬 수 있으므로 나눈다.

```powershell
flutter test integration_test/webview_all_malls_audit_test.dart -d emulator-5556 --dart-define=WEBVIEW_AUDIT_START=0 --dart-define=WEBVIEW_AUDIT_END=3
flutter test integration_test/webview_all_malls_audit_test.dart -d emulator-5556 --dart-define=WEBVIEW_AUDIT_START=3 --dart-define=WEBVIEW_AUDIT_END=64
```

Python 엔진의 마지막 기록된 전체 검증:

- 비통합 테스트 261개 통과
- 실네트워크 통합 테스트 2개 통과

Python 엔진을 변경하면 현재 Windows Python/프로젝트 의존성으로 다시 검증하고, 실행하지 않은 테스트를 통과했다고 보고하지 않는다.

## 9. WebView 안정화 다음에 남는 엔진 단계

1. Android WebView 안정화 및 64개 재감사
2. iOS 실물 기기에서 동일 대표 URL 감사
3. Android와 iOS 차이를 반영한 공통/플랫폼별 로딩 정책
4. 반스 상품명 누락 수정
5. 현대Hmall·리바이스·나이키·이랜드몰 NO_RESULT 원인 분리
6. 11번가 script/native timeout 격리
7. 다중 통화 모델 추가
   - 통화 코드
   - 소수 가격 보존
   - Gap/NUGU 지원 재검토
8. LF몰 렌더링 옵션·재고 데이터 지원 여부 결정
9. SHEIN 조건부 가격을 안전하게 분리할 수 있는지 재조사
10. 실패 시 앱 UX 구현
    - 상품명·이미지·URL은 저장
    - 가격만 사용자 입력
    - 차단/지원 통화/품절/불명확 사유 표시
11. Python 서버 폴백은 채택하지 않음. `parsing-engine/` 삭제 (0.9)
12. 쇼핑몰 규칙은 `product_extract_js.dart`가 단일 기준이다

## 10. 기록 파일

- 전체 프로젝트 개요: `C:\0.My_Project\17.SoftStudio\PROJECT_OVERVIEW.md`
- 가격 스키마: `flutter_app/lib/models/models.dart` (`ParsedProductInfo`), 규칙은 `product_extract_js.dart`
- 쇼핑몰 상세 조사: `C:\0.My_Project\17.SoftStudio\0.EngineTest\data\MALL_ADAPTER_PROGRESS.md`
- Android 최초 원본 결과: `C:\0.My_Project\17.SoftStudio\0.EngineTest\data\webview_android_audit_64_2026-08-16.json`
- 변경 이력: `CHANGELOG.md`
- WebView 가격 규칙: `flutter_app/lib/services/product_extract_js.dart`
- WebView 실행기: `flutter_app/lib/services/webview_scraper.dart`
- Android 64개 감사 러너: `flutter_app/integration_test/webview_all_malls_audit_test.dart`

## 11. 안전 규칙

- 로그인·결제·사용자 데이터 삭제 금지
- 사용자가 담은 장바구니 상품을 구분할 수 없으면 삭제하지 않음
- 실물 기기 앱 제거 또는 데이터 초기화 금지
- `git reset --hard`, `git checkout --`, `git clean` 금지
- dirty/untracked 파일을 기존 작업으로 간주하고 보존
- 관리 쇼핑몰 전용 가격 규칙 실패 시 범용 JSON-LD/OG/DOM 가격으로 우회하지 않음
- 틀린 가격보다 `null`이 안전함
- 차단 사이트를 우회하거나 로그인 세션을 자동으로 만들지 않음

## 12. 다음 대화 시작 프롬프트

**Tab S7 실페이지 대조를 이어서 할 때:** `wishlist-appversion2/TAB_S7_LIVE_COMPARE_CONTINUATION.md` 안의 시작 프롬프트를 새 대화에 붙여 넣는다. 브랜치는 `feat/webview-scraper-stabilize` (PR #28). 머지하지 않는다.

아래는 예전 WebView 안정화용 프롬프트다.

```text
GitHub의 `feat/webview-engine-handoff` 브랜치를 checkout한 뒤 C:\0.My_Project\17.SoftStudio\2026-softstudio-project\wishlist-appversion2\ENGINE_DEVELOPMENT_HANDOFF.md를 먼저 끝까지 읽고 wishkit 엔진 개발을 이어서 진행해줘.

현재 우선순위는 Flutter WebView 안정화다. webview_scraper.dart에 리다이렉트/SPA 안정 대기, evaluateJavascript timeout, 명시적 차단 조기 종료, 빈 결과 1회 재시도, 동일 가격 fingerprint 2회 확인, 실패 이유 분류를 보수적으로 구현해줘. 단순히 대기 시간만 늘리지는 마.

구현 후 단위 테스트와 analyze를 실행하고, SuperDisplay ADB 충돌이 해소된 경우 Android 에뮬레이터에서 WEBVIEW_AUDIT_ONLY=14,22,24,46,49,53,55를 먼저 검증한 다음 64개 전체 감사를 진행해줘. ADB 충돌이 계속되면 실물 기기의 앱이나 데이터를 삭제하지 말고 정확히 미검증으로 기록해줘.

현재 작업 트리는 dirty 상태이므로 reset/checkout/clean을 하지 말고 기존 변경을 보존해줘. 로그인·결제·사용자 데이터 삭제·장바구니 전체 삭제는 하지 마.
```
