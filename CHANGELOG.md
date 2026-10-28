# 변경 이력 (CHANGELOG)

## 2026-10-28 - 태그 찾기: 무신사 검색 단계 빼고 구글 검색으로 공식몰 연결 · 폴더 정리 · WebView 자료 정리

🌟 **쉬운 설명**
- 태그 사진으로 찾을 때 **무신사 검색창을 먼저 쓰던 단계를 뺐어요.** 이제 처음부터 구글 검색(Gemini)으로 브랜드 공식 홈페이지를 찾고, 공식몰에 없을 때만 쇼핑몰 페이지를 보여 줘요. 구글 검색은 유료 키가 있어야 동작해요.
- 구글 검색 한도를 넘으면 "공식몰 검색(구글 검색) 한도를 넘었어요"라고 알려 줘요.
- 공식몰이 아닌 곳에서 찾았을 때 문구를 "○○에서 찾았어요 (브랜드 공식몰에서는 확인하지 못했어요)"로 바꿨어요.
- 폴더를 알아보기 쉽게 바꿨어요. 앱은 `app/`, 엔진은 `engine/`, 문서는 `docs/`. 엔진 정답지(골든셋)는 `engine/testdata/golden_catalog.json`.
- 지금 코드와 안 맞는 예전 WebView 추출기 문서·감사 로그는 레포에서 뺐어요(깃 기록에는 남아 있음).

🔧 **기술 설명**
- 엔진: `mall_search.py` 삭제. `tag_identify.identify` 는 태그 읽기 → Gemini + Google 검색 그라운딩 → 후보 확인(공식몰 + 품번 확인이면 즉시 종료)만 한다. `search_match` 근거·`GOOGLE_RESERVE_S`·`PageView.html` 제거(main.py 도 같이). 검색 실패 note 를 429/그 외로 나눔(`_search_fail_note`). 테스트: 무신사 테스트 대신 2개(무신사 페이지를 열지 않음, 429 안내).
- 앱: `search_match` 분기 제거(`needsUserCheck` 는 다시 `name` 만), 공식몰 아님 문구 변경.
- 옮긴 것: `wishlist-appversion2/flutter_app` → `app`, `wishlist-appversion2/parsing-engine` → `engine`, `golden_catalog.json`·`bakeoff_results_run6_final.json` → `engine/testdata/`, `engine/tools/*_result*.json` → `engine/testdata/results/`, `REPORT_*.md` → `docs/reports/`(날짜-주제 이름), `CHANGELOG.md` → 레포 맨 위, `TEAM_CONTRACT.md` → `docs/`, `run_app.sh` → `scripts/`.
- 지운 것(WebView 시절): `ENGINE_DEVELOPMENT_HANDOFF.md`, `PRICE_SPLIT_HANDOFF.md`, `TAB_S7_LIVE_COMPARE_CONTINUATION.md`, `IOS_WEBVIEW_AUDIT_PROMPT.md`, `MALL_SUPPORT.md`, `audit-logs/`, `ios_webview_recheck_2026-08-17.json`, `share_intake_smoke_2026-08-17.json`. 원본은 커밋 `8db873f` 에서 `git show 8db873f:wishlist-appversion2/<파일>` 로 꺼낼 수 있다.
- 경로 설정: `amplify.yml`(appRoot `app`), `.gitignore`(하위 `.gitignore` 합침, `.env.example` 예외 경로), `scripts/check_secrets.sh`, `scripts/prepare_repo.sh`, `scripts/run_app.sh`. 주석 속 경로도 새 위치로.
- AWS 리소스 이름(`wishkit-parsing-engine` 등)은 그대로.
- ⚠️ Amplify 콘솔: 모노레포 앱 루트를 `app` 으로(환경 변수 `AMPLIFY_MONOREPO_APP_ROOT=app`). ⚠️ 엔진 반영은 `bash engine/deploy/engine.sh deploy`.

---

## 2026-10-26 - 무신사 품번 검색 결과를 "검색 일치"로 받아 주기

🌟 **쉬운 설명**
- 무신사에서 품번으로 검색해 상품이 1~2개만 나오면, 그 상품 페이지에 품번이 안 적혀 있어도 브랜드나 태그 가격이 보이면 찾은 것으로 보여 줘요. 이때는 "같은 상품인지 확인해 주세요"라고 안내해요.

🔧 **기술 설명**
- 2026-10-26 로그: 무신사 검색 '93251TTL1202' → 상품 1개(`products/5046318`), 그런데 페이지 글자에 품번이 없어 탈락 → 구글 검색 429 → 못 찾음.
- `verified_by="search_match"`: 쇼핑몰 품번 검색 결과가 `SEARCH_MATCH_MAX_RESULTS`(2)개 이하이고 페이지에 브랜드(영문 그대로) 또는 태그 가격이 있을 때. 근거 단계는 품번 확인(0)과 이름만(2) 사이(1). 품번 확인이 아니므로 구글 검색도 시도하고, 거기서 품번이 확인된 페이지가 나오면 그쪽을 고른다.
- 못 찾았을 때 쇼핑몰 후보를 열어 봤으면 그 이유를 note 로(검색 실패 대신).
- 앱: `needsUserCheck`에 `search_match` 포함, 안내 문구 추가.
- 테스트 5개 추가.

---

## 2026-10-26 - 태그 찾기: 무신사에서 먼저 찾고, 없을 때만 구글 검색

🌟 **쉬운 설명**
- 태그 사진으로 찾을 때 먼저 **무신사 검색창에 품번을 넣어** 찾아요(AI·구글 검색을 안 써서 무료, 한도 없음).
- 무신사에 없을 때만 Gemini 구글 검색을 써요. 무료 키는 구글 검색 한도가 0이라, 유료 키가 있어야 이 단계가 동작해요.

🔧 **기술 설명**
- 새 `mall_search.py`: 쇼핑몰별 검색 주소·상품 링크 모양(`MallSearch`). 무신사는 `/search/goods?keyword=` → `/search/musinsa/goods?q=` 순으로 시도, 상품 링크 `/products/<번호>`. 주소가 바뀌면 `MUSINSA_SEARCH_URLS` 환경변수로 바꿀 수 있다.
- `tag_identify.identify`: ① 쇼핑몰 검색 결과 앞 3개를 열어 품번 확인 → 확인되면 끝 ② 아니면 Gemini 구글 검색. 두 단계가 같은 확인 규칙(`_Checker`)을 쓴다. 쇼핑몰 단계는 구글 검색 몫 10초를 남기고, 검색 페이지가 막히면 바로 구글 검색으로 넘어간다.
- `PageView.html`(정제된 HTML)로 검색 결과의 상품 링크를 꺼낸다.
- 테스트 7개 추가(무신사에서 찾음·구글 검색 안 씀, 두 번째 검색 주소, 막힘 → 바로 구글, 시간 몫 등).
- 앱·백엔드 변경 없음(엔진만 `engine.sh deploy`).

---

## 2026-10-26 - 태그 사진 찾기: 못 찾은 이유 보여 주기·기록 남기기

🌟 **쉬운 설명**
- 태그는 읽었는데 판매 페이지를 못 찾으면, 이제 **왜 못 찾았는지**(시간이 모자람 / 품번이 적힌 페이지가 없음 / 검색 실패 등)를 한 줄로 보여 줘요.

🔧 **기술 설명**
- 엔진 `/identify-tag`: 요청마다 한 줄 요약 로그(`[identify] …`) — 읽은 브랜드·품번, 단계별 시간(read_tag·search·render), 열어 본 후보와 탈락 이유. 사진은 남기지 않음.
- 못 찾은 이유(`note`)를 사람이 읽는 문장으로(`_not_found_note`), 검색 실패의 원문은 로그로만.
- 앱: 못 찾았을 때 `이유: …` 줄을 보여 준다(서버가 보내던 note 를 화면에 안 쓰고 있었음).

---

## 2026-10-24 - 광고 카드를 상품 카드와 같은 크기로

🌟 **쉬운 설명**
- 목록 사이 광고가 상품 카드보다 훨씬 크게(빈 회색 칸까지) 보이던 문제를 고쳤어요. 이제 광고도 상품 카드와 같은 높이·모서리·그림자예요.

🔧 **기술 설명**
- 원인: `AdWidget`은 자기 크기가 없어 주어진 최대 크기까지 늘어나는데 최대 높이가 200이었다(내용은 약 90). 위에 "광고" 줄이 따로 있어 더 커졌다.
- 새 `lib/theme/list_card.dart`(`ListCardMetrics`: 높이 100·모서리 14·그림자 0.6). `WishlistProductCard`(내 위시리스트·친구 공유 위시리스트 공통)는 최소 높이 100, `NativeAdCard`는 높이 100 고정. 따로 붙이던 "광고" 줄은 빼고 템플릿의 "Ad" 표시를 쓴다(회색 바탕으로 상품과 구분 유지).

---

## 2026-10-24 - 무신사 앱 공유 링크(짧은 링크)도 읽기

🌟 **쉬운 설명**
- 무신사 앱에서 공유하면 `musinsa.onelink.me/…` 같은 짧은 링크가 오는데, 서버가 이걸 그대로 열다가 시간이 다 돼서 못 읽었어요. 이제 짧은 링크를 먼저 실제 상품 주소로 바꾼 뒤 읽어요.
- 저장되는 상품 링크도 짧은 링크가 아니라 실제 상품 주소(`musinsa.com/products/…`)예요.

🔧 **기술 설명**
- 원인(2026-10-24 로그): 엔진이 `https://musinsa.onelink.me/PvkC/…` 를 휴대폰 UA 로 열어 앱/스토어로 넘기려다 `Page.goto Timeout 20000ms`.
- 엔진: 새 `share_links.py` — 짧은 링크(onelink.me·app.link·page.link·naver.me·link.coupang.com 등)는 렌더링 전에 HTTP 리다이렉트를 PC 브라우저인 척 따라가 실제 주소를 얻는다. 앱 주소(`intent://`, `musinsa://`)가 나오면 `af_web_dp`·`browser_fallback_url` 등에서 웹 주소를 꺼내고, JS 로 넘기는 중간 페이지면 본문에서 쇼핑몰 이름(`musinsa`)이 든 주소만 고른다(추측하지 않음). 못 풀면 원래 주소로 진행. 총 4초 이내.
- `render.py`: `onelink.me` 를 모바일 UA 목록에서 뺐다.
- 시간 예산: 엔진 페이지 로딩 대기 20초 → 12초(`RENDER_NAV_TIMEOUT_MS`, `engine.sh`). 전체 25초 안에 AI 시간을 남긴다.
- GraphQL `ExtractedProduct.productUrl` 추가(엔진 `render.final_url`). 앱은 이 주소를 저장한다.
- 테스트: `test_share_links.py`(14개, 실제 HTTP 302 체인 포함), `parsing_bridge_test.dart` 2개 추가.
- ⚠️ 순서: 백엔드 배포(push) → `engine.sh deploy` → 앱 재설치. 앱을 먼저 깔면 서버에 아직 없는 `productUrl` 을 물어서 실패한다.

---

## 2026-10-24 - 서버 함수 3개가 호출될 때마다 실패하던 문제

🌟 **쉬운 설명**
- 서버 AI 상품 읽기, 태그 사진 찾기, 친구에게 살까말까 보내기·댓글·팔로우 알림, 공개 위시리스트 보기가 서버에서 바로 실패하고 있었어요. 고쳤어요.
- 앱은 바꾸지 않아도 돼요(백엔드만 다시 배포).

🔧 **기술 설명**
- 원인: Amplify Gen 2 의 `a.handler.function()` 은 Lambda 에 `{ typeName, fieldName, arguments, identity, … }` 를 넘기는데(@aws-amplify/graphql-function-transformer), 세 함수 모두 AppSync 직접 리졸버 모양인 `event.info.fieldName` 을 읽어서 `Cannot read properties of undefined (reading 'fieldName')` 로 실패했다(2026-10-24 CloudWatch 로그).
- `functions/shared/appsync-event.ts`(`AmplifyFunctionEvent`, `fieldNameOf`) 추가. parsing-proxy·social-actions·public-wishlist 핸들러가 이걸 쓴다. `info` 모양도 받아 둠.
- `engine.sh`: 시작할 때 AWS CLI·로그인·(deploy 면) Docker 를 먼저 확인하고, 권한 오류는 원문 그대로 보여 준다(전에는 "기본 VPC 가 없어요"로 잘못 안내).

---

## 2026-10-24 - 상품 읽기를 서버 AI 로 일원화 (WebView 추출기 제거)

🌟 **쉬운 설명**
- 상품 링크를 넣으면 이제 휴대폰이 아니라 **서버의 AI**가 페이지를 읽어서 이름·가격·사진을 채워요(9월 18일 결정을 앱까지 반영).
- 서버 엔진이 꺼져 있으면 자동으로 안 채워지고, "자동 읽기 서버가 꺼져 있어요" 안내와 함께 직접 입력하면 돼요.
- 로그인해야 자동 읽기가 돼요. 가격 새로고침도 같은 방식이에요.

🔧 **기술 설명**
- 앱: `ParsingBridge`가 GraphQL `extractProduct`를 부른다(새 `Gql.extractProduct`). 응답→모델 변환과 오류 해석은 새 `lib/services/server_extract.dart`(순수 Dart). 실패해도 예외 대신 URL·공유 제목을 남기고 `ExtractFailureReason`(not_logged_in/engine_off/timeout/network/failed/ambiguous)으로 화면 문구를 고른다.
- 제거: `webview_scraper.dart`, `webview_extract_host.dart`(앱 전체에 깔린 숨은 WebView), `product_extract_js.dart`, `live_field_compare.dart`, `flutter_inappwebview`·`integration_test` 의존성, WebView 단위·통합 테스트, `tools/`(WebView 대조용 파이썬 스크립트). `ParsedProductInfo`에서 WebView 전용 필드(`onDeviceExtracted`, `mergeOnDevice`, 옵션·근거·Tier 필드) 정리.
- 서버: `parsing-proxy`가 오류를 코드로 돌려준다(`ENGINE_NOT_CONFIGURED`·`ENGINE_UNAVAILABLE`·`ENGINE_TIMEOUT`·`ENGINE_ERROR`·`INVALID_INPUT`, 자세한 원인은 CloudWatch). AppSync 30초 한도에 맞춰 엔진 요청 27초·Lambda 30초, 엔진 태스크는 `EXTRACT_TIMEOUT_S=25`(`engine.sh`). 원래 /extract 는 55초를 기다려서 AppSync 에서 먼저 끊겼다.
- 테스트: `parsing_bridge_test.dart`(9개)·`price_refresh_test.dart`를 서버 응답 기준으로 다시 씀(`test/fake_extract_gql.dart`).
- 기록 문서(`ENGINE_DEVELOPMENT_HANDOFF.md`, `MALL_SUPPORT.md`) 맨 위에 WebView 제거 안내를 달았다. 내용은 기록으로 남김.

---

## 2026-10-24 - 공유한 상품 URL 이 여러 번 들어가던 문제

🌟 **쉬운 설명**
- 아이폰에서 쇼핑몰 상품을 우리 앱으로 공유하면 입력칸에 같은 주소가 3~4번 들어가고, 주소가 띄어쓰기 없이 붙어 들어오면 상품을 못 읽던 문제를 고쳤어요.
- 이제 같은 주소는 한 번만 들어가고, 저장할 때도 첫 주소 하나만 상품 URL 로 저장돼요.

🔧 **기술 설명**
- 원인: iOS 공유 시트가 한 번에 같은 URL 을 공유 글·URL 첨부·텍스트 첨부로 넘기고, `AppDelegate`가 첨부 경로를 한 번 더 붙였다. URL 이 붙어 들어오면 `ShareInput.firstUrl`이 `https://a/1https://a/1…` 전체를 주소 하나로 돌려줘서 읽기에 실패했다. 저장 시에는 읽은 주소가 없으면 입력칸 글 전체가 `productUrl`에 들어갔다.
- `ShareInput.normalize()` 추가(줄·URL 중복 제거, 붙은 같은 URL 하나로; `?to=https://…` 같은 정상 주소는 자르지 않음). `main.dart`·`share_intake_screen.dart`에서 사용. 저장 시 `productUrl`은 입력칸의 첫 URL.
- iOS: `ShareViewController.uniqueMessages`(같은 글·다른 글에 포함된 글 제외), `AppDelegate`는 공유 글에 이미 있는 URL 을 다시 붙이지 않음.
- 테스트 6개 추가(`share_input_test.dart`).

---

## 2026-10-23 - 공용 백엔드 자동 배포 · 엔진 켜고 끄기

🌟 **쉬운 설명**
- GitHub `main`에 올리면 백엔드가 자동으로 배포돼요(Amplify 콘솔 연결 필요). 팀원은 각자 sandbox를 안 켜도 돼요.
- 엔진 서버는 `parsing-engine/deploy/engine.sh`로 시연·테스트할 때만 켜고 끌 수 있어요. 켜져 있는 동안만 요금이 나가요.

🔧 **기술 설명**
- 레포 맨 위 `amplify.yml`: 백엔드 전용 Amplify 앱(모노레포, appRoot `wishlist-appversion2/flutter_app`). `npm ci` 대신 `npm install` — `@aws-amplify/data-construct`의 묶음 패키지 때문에 잠금 파일을 새로 만들어도 `npm ci`가 실패한다(npm 10·11 공통).
- `package-lock.json` 갱신(`package.json`과 맞춤).
- Amplify 콘솔 환경 변수가 `ampx pipeline-deploy` 안의 backend.ts 까지 전달되지 않는 문제(배포 2번 로그로 확인) → `amplify.yml`이 `ENGINE_*` 값을 `amplify/.engine.env`(gitignore)로 옮겨 적고, 새 `amplify/engine-env.ts`가 `process.env` → 그 파일 순으로 읽는다.
- `engine.sh`: 기본 VPC 퍼블릭 서브넷 + 퍼블릭 IP(NAT·로드밸런서 없음), 들어오는 연결은 parsing-proxy Lambda 보안그룹의 8000번만. 주소는 Cloud Map `engine.wishkit.local`이라 껐다 켜도 백엔드 설정이 그대로. Gemini 키는 SSM SecureString. macOS 기본 bash(3.2)에서 동작 확인.

---

## 2026-10-23 - 살까말까를 링크로 SNS에 공유

🌟 **쉬운 설명**
- 살까말까 "공유하기"를 누르면 **앱 친구에게 보내기**와 **링크로 공유** 중에서 고를 수 있어요.
- 링크로 공유를 고르면 휴대폰 공유창이 떠서 카카오톡·인스타그램 DM·문자 등으로 바로 보낼 수 있어요. 받은 사람은 앱이 없어도 브라우저에서 상품을 볼 수 있어요.
- 링크는 **해외에서도 열려요**(앱 안 사진은 지금처럼 한국에서만). 링크는 28일 동안 열리고, 다시 공유하면 같은 주소로 28일이 새로 시작돼요.
- 마이페이지 "보낸 살까말까"와 살까말까 상세 화면의 버튼도 "공유하기"로 바뀌었고, 같은 선택창이 떠요.

🔧 **기술 설명**
- ⚠️ **백엔드를 먼저 배포해야 링크가 해외에서 열립니다.** 앱만 먼저 나가면 옛 배달망 주소로 링크가 만들어져 지금처럼 한국에서만 열려요(오류는 없음).
- `backend.ts`: 공유 페이지 전용 CloudFront 배달망 `SharePagesCdn` 추가 — 나라 제한 없음, `originPath: /share-pages`로 그 폴더만 연결. 기존 `FilesCdn`(한국 전용)과 캐시 정책은 그대로 같이 씀. `amplify_outputs`의 `custom.sharePagesBaseUrl`로 주소 전달.
- `share_plus: ^13.3.1` 추가 → `flutter pub get` 필요. 11.x는 다른 패키지와 충돌해서 설치가 안 됐다. 13.x에 맞춰 Android 빌드 도구를 올림: AGP 8.10.1→8.12.1, Gradle 8.12→8.13, Kotlin 2.1.0→2.2.0.
- 새 파일 `lib/screens/share/share_link.dart`(공유 방법 선택창·공유창 띄우기, 공유창 실패 시 링크 복사). 쓰이지 않던 `copy_public_share_link.dart`와 가짜 주소를 만들던 `AppStore.shareUrlFor`는 삭제.
- `AppStore.publishSelectedBasketLink()` 추가. 로그인 확인을 먼저 해서, 실패했을 때 "보낸 살까말까"에 빈 기록이 남지 않게 함. `publishSharePage()`는 화면이 옛 basket을 넘겨도 최신 값(같은 공유 주소)을 쓰도록 수정.
- `AwsFileStore.sharePageUrlFor()`: 공유 페이지만 공유 전용 배달망 주소로 만든다. 테스트 2개 추가(`file_store_test.dart`).
- 공유 페이지에는 기존처럼 상품 메모·고민 이유가 들어가지 않음(친구 공개 범위와 같음).

---

## 2026-10-23 - 태그 사진으로 찾기 정확도 개선

🌟 **쉬운 설명**
- 태그에 색상 번호까지 붙은 품번(예: 485454-26)도, 쇼핑몰 페이지에 색상 없이 적혀 있으면 이제 찾아요.
- 매장에서 붙인 가격 스티커 번호를 품번으로 잘못 읽어도, 태그에 같이 적힌 진짜 품번으로 다시 확인해요.
- 바코드 숫자를 잘못 읽으면(검증 숫자가 안 맞으면) 그 바코드는 쓰지 않아요.
- 앱은 바뀌지 않았어요(서버만 배포).

🔧 **기술 설명**
- 바코드는 AI가 읽은 숫자를 서버가 검증 숫자로 확인하는 방식(앱 변경 없음). 휴대폰 바코드 판독(ML Kit)은 보류.
- 새 모듈 `tag_codes.py`(GTIN 검증 숫자, 기본 번호/색상 분리, 페이지 코드 확인). 모든 브랜드가 같은 경로(태그 읽기 → 검색 → 페이지 확인)를 탄다 — 브랜드별 예외 규칙 없음.
- 태그 스키마에 `other_codes` 추가. 응답 `tag`에 `barcode_rejected`(버린 바코드), `match`에 `tag_price_seen` 추가 —
  앱·Lambda가 쓰는 필드는 그대로라 하위 호환.
- `verified_by`에 `product_code_base`(색상을 뗀 기본 번호/다른 코드로 확인) 추가. 앱은 `name`일 때만 확인을 묻는다.
- 후보 순위: 이름으로만 확인 → 공식몰 여부 → 코드 근거 세기 → 태그 가격 순. 공식몰에서 코드로 확인되면 즉시 종료.
- 테스트: `test_tag_codes.py` 신규, `test_tag_identify.py`에 4개 추가. 새 기능과 무관한 경우는 이전 코드와 결과 동일(무작위 5,000건 비교).

---

## 2026-10-23 - 태그 사진 찾기 서버 코드 정리 · 시간 초과 보완

🌟 **쉬운 설명**
- 태그 사진으로 찾기가 사람이 몰릴 때 25초를 다 쓰고 실패하던 경우를 줄였습니다. 이제 시간이 모자라면 기다리지 않고, 태그에서 읽은 정보라도 앱에 돌려줍니다(앱은 그 정보로 직접 입력 화면을 보여줌).
- 기능·결과는 그대로입니다.

🔧 **기술 설명**
- `main._render_for_identify`: 렌더링 슬롯(`render_semaphore`) 대기 시간도 `budget_s` 안에 포함. 원래는 /extract로 슬롯이 다 차 있으면 무한정 기다리다 전체 504 → 태그 정보까지 잃었음.
- `providers.generate(max_retry_wait_s=...)`: 429 재시도 대기가 남은 시간보다 길면 바로 실패로 돌려줌. /identify-tag는 남은 시간 − 2초를 상한으로 넘긴다.
- /identify-tag: base64 길이로 큰 사진을 디코딩 전에 413으로 거름.
- `providers._generate` / `_to_gemini_schema` → `generate` / `to_gemini_schema`(tag_identify.py가 다른 모듈의 비공개 이름을 가져다 쓰던 것 정리).
- `tag_identify.py`: 품번·바코드 길이·이름 일치 비율을 상수로, 후보 기록(`candidates_checked`) 생성 중복 제거, 페이지 글자 정규화를 한 번만. 결과는 원본과 동일(무작위 입력 비교로 확인).
- `parsing-proxy`: 모르는 GraphQL 필드가 /extract로 흘러가던 것을 `Unknown field` 오류로 막음.
- 테스트 추가: `test_providers.py`(재시도 대기 상한), `test_main.py`(슬롯 대기 시간 초과·큰 사진 413).

---

## 2026-10-22 - 태그 사진을 상품에 함께 저장

🌟 **쉬운 설명**
- 태그 사진으로 담은 상품은 그 태그 사진도 함께 저장됩니다. 상품 상세 페이지의 "고민하는 이유" 아래에 작은 미리보기가 생기고, 누르면 크게 볼 수 있습니다(두 손가락으로 확대 가능).
- 태그 사진은 **나만 봅니다.** 친구 위시리스트나 살까말까로 보낸 바구니에는 들어가지 않습니다. 상품을 지우면 사진도 같이 지워집니다.

🔧 **기술 설명**
- ⚠️ **백엔드를 먼저 배포해야 합니다.** `WishProduct.tagImageUrl` 필드를 추가해서, 새 앱이 옛 백엔드에 붙으면 상품 목록을 불러오지 못합니다(GraphQL 필드 없음).
- S3 `tag-photos/{entity_id}/*` 폴더 추가(주인만 쓰기·지우기). 파일 이름은 128비트 무작위 값, 주소는 주인의 상품 기록에만 저장.
- `Product.tagImageUrl` — `toJson`에는 넣지 않음(살까말까 전송에 쓰이므로). 공개 위시리스트 Lambda도 이 필드를 복사하지 않음.
- 저장 순서: 사진 업로드 → 상품 저장. 사진 업로드 실패 시 상품만 저장하고 안내. 상품 저장 실패·중복 시 올린 사진을 지움.
- 회원 탈퇴 시 `tag-photos` 폴더도 삭제.

---

## 2026-10-22 - 상품 카드 사이 광고 (AdMob 네이티브)

🌟 **쉬운 설명**
- 내 위시리스트와 친구 위시리스트에서 상품 6개마다 광고 카드 1개가 들어갑니다. 상품 카드(흰색)보다 한 톤 어두운 회색 바탕에 "광고" 표시가 붙어서 광고인 걸 바로 알 수 있습니다.
- 광고를 못 불러오면 그 칸은 아예 사라집니다(빈 박스 없음). 상품이 6개 이하인 목록에는 광고가 없습니다.

🔧 **기술 설명**
- `google_mobile_ads: ^9.1.0` 추가 → `flutter pub get` 필요(pubspec.lock 미갱신). Android `minSdk` 23→24(플러그인 요구).
- `lib/ads/`: `AdFeed`(광고 칸 위치 계산, 순수 Dart), `AdsConfig`(간격·광고 단위 ID), `NativeAdCard`(작은 네이티브 템플릿 + 회색 카드 + "광고" 표시).
- 광고 단위 ID는 `--dart-define=ADMOB_NATIVE_ANDROID/IOS`로 넣는다. 안 넣으면 구글 테스트 광고가 나온다.
- AndroidManifest / Info.plist의 AdMob **앱 ID는 지금 구글 테스트 ID** — 출시 전에 실제 값으로 교체.
- 웹·데스크톱·`flutter test`에서는 광고 칸 자체를 만들지 않는다(`AdsConfig.supported`).

---

## 2026-10-22 - 태그 사진으로 상품 담기

🌟 **쉬운 설명**
- 담기 화면에 "태그 사진으로 찾기" 버튼을 추가했습니다. 옷 태그를 찍으면 품번을 읽고, 브랜드 공식몰에서 그 상품 페이지를 찾아 담습니다. 공식몰에 없으면 무신사·29CM 같은 쇼핑몰에서 찾고, 어디서 찾았는지 화면에 보여줍니다.
- 품번이 페이지에 실제로 있는지 확인된 경우에만 "찾았다"고 합니다. 못 찾으면 태그에서 읽은 이름만 채우고 가격은 직접 입력합니다(태그 가격은 정가라서 자동으로 넣지 않음).
- 상품 상세 페이지에 "가격 새로고침" 버튼을 추가했습니다(같은 날 작업).

🔧 **기술 설명**
- 엔진: `POST /identify-tag` (`parsing-engine/server/tag_identify.py`). Gemini 비전으로 태그 읽기 → Gemini + Google 검색 그라운딩으로 후보 URL → Playwright로 후보 페이지를 렌더링해 품번 확인 → URL 반환. 가격은 읽지 않음 — 앱이 기존 URL 담기 경로(WebView)로 읽음.
- AppSync 리졸버 30초 한도 때문에 엔진 25초 / Lambda fetch 27초로 맞춤. 기존 `extractProduct`(엔진 45초 / fetch 55초)도 같은 한도에 걸리므로 앱 연결 전에 정리 필요.
- Amplify: `identifyProductTag` 쿼리 + `IdentifiedTag` 타입. 기존 `parsing-proxy` Lambda가 `fieldName`으로 두 쿼리를 나눠 처리(VPC 설정 재사용).
- 앱: `AccountRepository.identifyProductFromTag` → `AwsProductTagStore`. `ShareIntakeScreen`에 카메라/앨범 선택(1280px · JPEG 75%).
- 정확도 측정: `parsing-engine/tools/tag_identify_check.py` (태그 사진 + 정답 CSV).
- 미검증: 실제 Gemini 호출, Amplify 배포, Flutter 빌드. 서버 단위·엔드포인트 테스트와 TS 타입 체크만 통과.

---

## 2026-08-21 - PRICE 브랜치 통합 · 몰 지원 목록

🌟 **쉬운 설명**
- 기기 소유자(SPA)와 팀원(Cafe24) 가격 패치를 안정화 브랜치에 합쳤고, 지원하는 쇼핑몰·지원하지 않는 쇼핑몰 목록을 문서로 남겼습니다.

🔧 **기술 설명**
- `fix/price-owner-spa` · `fix/price-teammate-cafe24` → `feat/webview-scraper-stabilize` 병합.
- [`MALL_SUPPORT.md`](./MALL_SUPPORT.md): Tab MATCH 50몰 / 기권·차단 / 미인증 몰 구분.
- ENGINE 핸드오프 상단에 2026-08-21 현황 추가.

---

## 2026-08-21 - 에이블리·SSG 보류 해소 (Tab MATCH 3)

🌟 **쉬운 설명**
- 보류했던 에이블리·SSG를 탭에서 각각 3개 상품 모두 맞췄습니다. 에이블리는 모바일 주소와 형제 서브도메인·SPA 안정화를 고쳤고, SSG는 만료된 딜 대신 살아 있는 딜 페이지의 새 가격 형식을 읽습니다.

🔧 **기술 설명**
- 에이블리: `m`→`mobile` 형제 서브도메인을 same-site로 인정(`registrableDomain`). SPA `onHistoryUpdate`가 settle을 막지 않음. 카탈로그 `mobile.a-bly.com`, #3 live 20000.
- SSG: `resultItemObj` 비탐욕 정규식 제거(script_timeout). deal `bestAmt:'N'` + itemView `parseInt` 모두 허용. 활성 deal 3개로 카탈로그 교체. itemView는 Tab에서 `access_blocked` 유지(우회 없음).
- Tab S7 MATCH 3×2.

---

## 2026-08-21 - 지그재그·롯데온 Tab MATCH 3 (카탈로그 정합)

🌟 **쉬운 설명**
- 지그재그는 최저가 도전(쿠폰)가가 아니라 화면 판매가로 카탈로그를 맞췄고, 롯데온과 함께 탭에서 3개씩 모두 맞았습니다.

🔧 **기술 설명**
- 지그재그 live: 15300/159000 → `display_final_price.final_price` 17000/179000 (additional/최저가도전 제외). 상품명 갱신.
- Tab MATCH 3 × 지그재그·롯데온. 11번가·이랜드몰은 기존 Tab MATCH 3 유지.

---

## 2026-08-21 - 올리브영·Aritzia·KREAM Tab MATCH 3

🌟 **쉬운 설명**
- 올리브영·Aritzia·KREAM을 탭에서 각각 3개 상품 모두 맞췄습니다. 올리브영은 느린 상품도 API로 가격을 기다리고, Aritzia는 원화로 바뀐 뒤의 장바구니 버튼을 보고, KREAM은 브랜드배송 상품으로 바꿨습니다.

🔧 **기술 설명**
- 올리브영: RSC 없으면 `goods/api/v1/detail` async fetch+폴링. sitePricing 대기 중 name/image만 나오면 scraper 조기종료 → 빈 응답으로 폴링 유지. #2 SKU `A000000262781` @25900.
- Aritzia: Global-e KRW(≥10000)만 채택. `Add to Bag` 버튼 ₩ 우선, URL `color=` 고정. maxWait 45s.
- KREAM: 입찰 SKU → 브랜드배송 `1012767`/`1012757`/`1012784`.
- Tab S7 MATCH 3×3. 에이블리·SSG 보류.

---

## 2026-08-20 - PRICE 배치: 미쏘·립합·마하그리드 정가

🌟 **쉬운 설명**
- 미쏘·립합·마하그리드도 회원가가 아니라 정가로 읽도록 바꿨고, 탭에서 3개 몰 모두 맞았습니다.

🔧 **기술 설명**
- `mixxo.com` / `liphop.com` → `cafe24MetaList`.
- `mahagrid.com`: `product:price:amount` 채택, Offer availability 완화. #2 SKU `3852`→`3854`.
- Tab MATCH 3×3.

---

## 2026-08-20 - 프롬비기닝 정가 · 나이키/CJ 카탈로그 · 이름 따옴표

🌟 **쉬운 설명**
- 프롬비기닝도 회원가 대신 정가로 읽도록 바꿨고, 나이키·CJ는 오래된 할인가 카탈로그를 고쳤습니다. 상품명 따옴표 차이만으로 틀리던 것도 맞춰 봤습니다. 탭에서 프롬비기닝·나이키는 3개 모두 맞았고, CJ는 2번 상품만 가격을 아직 못 읽습니다.

🔧 **기술 설명**
- `frombeginning.co.kr` → `cafe24MetaList`. LD가 옵션가만 있어도 `product_price` 정가 허용.
- 나이키 live 99000/65000→189000/115000. CJ #1 live 129000→169000.
- `normalizeProductName`: 따옴표 제거. 프롬비기닝 #3 이름·이미지 갱신.
- Tab: 프롬비기닝·나이키·CJ온스타일 모두 MATCH 3.
- `cjonstyle`: 장바구니만 있는 SKU 허용, Offer 복수여도 동일 KRW InStock 단가면 채택.

---

## 2026-08-20 - 회원가 몰 정가 채택 + W컨셉 카탈로그

🌟 **쉬운 설명**
- 리·필루미네이트·어반스터프·파브레가·비바스튜디오는 회원가 대신 정가로 읽도록 바꿨고, 탭에서 모두 맞았습니다. W컨셉 1번은 예전 할인가가 남아 있어 현재 판매가로 고쳤습니다.

🔧 **기술 설명**
- `cafe24MetaList`: `product:price:amount` / `product_price`를 채택. 리·비바는 metaSale → metaList.
- 필루미네이트·어반스터프·파브레가: 결과 price를 sale→regular로 변경. Tab MATCH 3×5.
- W컨셉 #1 live 29120→39000(현재 `SalePrice`). Tab MATCH 3.

---

## 2026-08-20 - 4910 WebView 가격 (NEXT_DATA vs innerText)

🌟 **쉬운 설명**
- 4910은 판매가가 화면 글이 아니라 페이지 데이터(__NEXT_DATA__)에만 있어서, 글만 찾으면 가격이 없다고 판단하고 있었습니다. 데이터 HTML까지 보도록 고쳤더니 탭에서 3개 모두 맞았습니다.

🔧 **기술 설명**
- `4910.kr`: 가격 존재 검증을 `pageText()`뿐 아니라 `documentElement.innerHTML`로 확장. Tab MATCH 3 (34800/47200/20800).

---

## 2026-08-20 - 더현대Hi 할인가 규칙 + live 가격 교정

🌟 **쉬운 설명**
- 더현대Hi는 정상가/할인가를 뒤집어 읽고 있었고, 카탈로그에도 잘못된 낮은 가격이 들어 있었습니다. 고친 뒤 탭에서 3개 모두 맞았습니다. 4910은 카탈로그 가격을 바로잡았지만 WebView에서는 아직 가격을 못 읽습니다.

🔧 **기술 설명**
- `hi.thehyundai.com`: `dcPrc`를 판매가·`sellPrc`를 정상가로 사용. `sellMdaPossYn` 누락 허용. 품절(qty=0) SKU는 카탈로그에서 `40B1406274`로 교체. Tab **MATCH ×3**.
- `4910.kr`: 카탈로그 live를 34800/47200/20800으로 교정, sno 매칭·CTA 완화·maxWait 20s. Tab은 이름·이미지만 맞고 `price_ambiguous` 유지(NEXT_DATA 경로 WebView 미확정).

---

## 2026-08-20 - 앤더슨벨 카탈로그 교체 · 에이블리 로드 시도

🌟 **쉬운 설명**
- 앤더슨벨에서 홈으로 튕기던 상품을 다른 상품으로 바꿨더니 탭에서 3개 모두 맞았습니다. 에이블리는 기다림·모바일 UA를 늘려도 페이지 로드가 끝나지 않아 당분간 보류합니다.

🔧 **기술 설명**
- 앤더슨벨 카탈로그 #2: `product_no=10277`(홈 리다이렉트) → `10280`. Tab MATCH 3.
- 에이블리: `firstLoadTimeout` 40s / `maxWait` 28s, 대조 하드 타임아웃 90s, 모바일 UA, same-site 외 로드 콜백 허용. Tab은 여전히 `loading_timeout`(onLoadStop 미발생). SSG deal/`script_timeout`·PC 403은 별도.

---

## 2026-08-20 - 이미지 몰 재검증 + 패션플러스 카탈로그/이미지

🌟 **쉬운 설명**
- 하고·룩핀은 탭에서 이름·가격·사진이 모두 맞았습니다. 패션플러스는 og 플레이스홀더 대신 상품 사진을 쓰도록 고치고, 딜 페이지를 일반 상품으로 바꿨더니 3개 모두 맞았습니다.

🔧 **기술 설명**
- Tab: 하고 MATCH 3, 룩핀 MATCH 3. SSG는 deal 페이지 `script_timeout`×3(카탈로그 교체 후보). 에이블리 `loading_timeout`×3, 앤더슨벨 1·3 MATCH / 2 `not_product_page`.
- 패션플러스: og `dev_test/og_200x200` 거부 → JSON-LD/DOM `product_img`; 옵션 버튼 비어 있으면 LD `sale_price` 폴백. 카탈로그 3상품 교체 → Tab MATCH 3.
- 더현대Hi·4910: 이름·이미지는 맞지만 `price_ambiguous`(live 가격 재확인 필요: 4910 1000/1690원 의심).
- 회원가 베이스라인(Tab): 어반스터프·파브레가 엔진가 = live×0.9(회원가). 필루미네이트도 엔진<live. 리·비바스튜디오는 `price_ambiguous`(가격 null). **정책 결정 전 엔진 변경 금지.**

---

## 2026-08-20 - Cafe24 metaSale: 빈 availability·custom span·HTML 이름

🌟 **쉬운 설명**
- 노이아고처럼 재고 표시가 비어 있어도 원화 가격이 맞으면 확정하고, 위드윤처럼 이름에 HTML이 섞여도 가격·이름이 맞게 나오도록 고쳤습니다. 탭에서 두 몰 모두 3개 일치했습니다.

🔧 **기술 설명**
- `cafe24MetaSale`: LD Offer `availability` 비어 있어도 KRW price면 meta 교차검증; `#span_product_price_text` 없으면 `#span_product_price_custom`; `stripHtmlName`으로 이름 HTML/`\u003c` 제거(위드윤·핫핑).
- Tab `R54RB01SMVB`: 노이아고 MATCH 3, 위드윤 MATCH 3(첫 시도 ADB 끊김 후 재시도).
- 단위: `product_extract_js_sync_test.dart` 통과. PR #28 Draft 유지.

---

## 2026-08-20 - Cafe24 verifiedCafe 가격 폴백 (코드그라피·립합)

🌟 **쉬운 설명**
- JSON-LD에 재고 가격이 비어 있어도, 메타·화면 판매가·스크립트가 같으면 가격을 확정하도록 고쳤습니다. 코드그라피·립합이 탭에서 맞게 나왔습니다.

🔧 **기술 설명**
- `verifiedCafe` / `cafe24MetaSale`: LD `InStock` 가격이 없으면 `product:sale_price:amount` + `#span_product_price_text` (+ `product_price`) 교차검증 폴백.
- Tab 재검증: 코드그라피 MATCH 3, 립합 MATCH 3. 위드윤 1 MATCH 후 2번 hang(ADB 리셋).

---

## 2026-08-20 - 대조 후 엔진 패치 1차 (W컨셉·핫핑·타이밍)

🌟 **쉬운 설명**
- 탭 대조에서 나온 문제를 고치기 시작했습니다. W컨셉은 상품 이름을 제대로 읽고, 핫핑은 이름에 섞이던 HTML을 지웁니다.

🔧 **기술 설명**
- W컨셉: `GA4ItemObj.ItemName`으로 상품명 추출. Tab 재검증 2·3 MATCH, 1은 PRICE(엔진 SalePrice 39000 vs live 29120).
- 핫핑: 이름 HTML 태그 제거 → Tab MATCH 3.
- 에이블리: `firstLoadTimeout` 15→25초. 앤더슨벨: `maxWait` 12→20초.
- Cafe24 `cafe24MetaSale` 조건 완화, 하고/룩핀/SSG/패션플러스 이미지 우선순위, 더현대Hi/4910 가격 규칙 조정.
- 코드그라피·립합 등 verifiedCafe `price_ambiguous`는 아직 남음(다음 패치).

---

## 2026-08-20 - Tab S7 50몰 실페이지 대조 완료

🌟 **쉬운 설명**
- 탭에서 쇼핑몰 50곳·상품 149개를 모두 정답지와 비교했습니다. 앱 동작은 바꾸지 않았고, 결과만 기록했습니다.

🔧 **기술 설명**
- 인수인계 §0.13, `TAB_S7_LIVE_COMPARE_CONTINUATION.md`, `audit-logs/compare-final-summary.json` 갱신.
- MATCH 전부 15몰: 무신사·29CM·FILA·탑텐·무인양품·현대Hmall·유니클로·게스·반스·후아유·아모멘토·예일·퀸잇·브랜디·SSF샵.
- 주요 이슈: W컨셉 이름, Cafe24 `price_ambiguous`, 에이블리 `loading_timeout`, og 플레이스홀더 이미지, 4910·더현대Hi live 재확인 후보.
- 대조 후 `flutter build apk --debug` + `adb install -r`로 Tab에 debug APK 복구. PR #28 Draft 유지, 머지 없음.

---

## 2026-08-18 - Tab S7 재대조 중간 상태를 인수인계로 남김

🌟 **쉬운 설명**
- 탭에서 쇼핑몰 50곳을 다시 대조하다가 코드그라피에서 멈춘 상태를, 다른 사람이 바로 이어서 돌릴 수 있게 적어 두었습니다. 앱 동작은 바꾸지 않았습니다.

🔧 **기술 설명**
- 이어서 하는 사람용: `wishlist-appversion2/TAB_S7_LIVE_COMPARE_CONTINUATION.md`. 인수인계 §0.13.
- 재실행 완료: 36몰 중 35몰 3/3(낫포유 2/2) + 코드그라피 1번 PRICE. 미실행 14몰(후아유·Aritzia·마하그리드 등).
- 분류는 틀린 필드 이름. `MATCH` = 세 필드 일치, `PRICE` = 가격만 불일치.
- 1몰씩 `--no-uninstall`. 대형 배치 hang, ADB `closed`, Gradle APK 잠금이 반복됨. 리바이스 대기·범용 가격 우회·PR 머지 없음.

---

## 2026-08-18 - 50몰 새 정답지 3상품씩 만들고 엔진과 대조

🌟 **쉬운 설명**
- 쇼핑몰마다 상품 페이지를 새로 열어 이름·가격·사진을 정답으로 적고, 탭에서 엔진이 같은 값을 읽는지 비교했습니다. 49몰은 정답이 채워졌고, 낫포유만 hang URL을 빼 2개입니다.

🔧 **기술 설명**
- `integration_test/live_field_compare_catalog.dart`를 2026-08-18 신규 상품으로 교체. 판매가는 화면 판매가(첫구매·카드 쿠폰 제외).
- 정답 3개 49몰(+낫포유 2). 브라우저로 채운 몰: 룩핀, 유니클로(판매가 49900·3x4 이미지), 반스, 코드그라피, SSF샵, 롯데온, Aritzia, 올리브영, 에이블리, 브랜디, 이랜드몰, 퀸잇.
- 퀸잇 판매가는 `product.finalPrice`(첫구매·최대쿠폰가 제외).
- 탭 S7 신규 정답 MATCH: 무신사·29CM·게스·후아유·예일·FILA·아모멘토·앤더슨벨·반스·SSF샵·유니클로·현대Hmall·퀸잇·브랜디·탑텐·무인양품 각 3, 위드윤·커버낫·데일리쥬·11번가·롯데온 2, Aritzia·지그재그·CJ온스타일·미쏘·나이키·올리브영 1, 이랜드몰 2.
- 이름·사진 맞고 가격만 불일치/`price_ambiguous`: 코드그라피(엔진 null), 프롬비기닝(~20% 낮음), 룩핀은 이름·가격 맞고 엔진 이미지가 `og_tag_lookpin_web.jpg`, 올리브영 2(`price_ambiguous`), 노이아고 3(엔진 null), SSG 3(엔진 null·이미지 stem 일치·URL 크기만 다름).
- 정답 카탈로그 오류로 엔진이 맞음(재수집 후 MATCH): 탑텐 3(9900/19900/12900), 무인양품 3(29900/29900/49900·og 제네릭 이미지).
- `loading_timeout`: 에이블리 3. W컨셉: 이름 `[W CONCEPT]`(1번 가격도 불일치), 2·3번은 가격·사진 일치.
- 이랜드몰 2번 IMAGE(엔진 이미지 날짜 경로가 live와 다름). 패션플러스 live `og_200x200.jpg`, 더현대Hi·4910 live 가격 이상은 이전과 동일.
- 앱 uninstall 없음. 검사 후 debug APK `-r` 복구.

---

## 2026-08-18 - 탭 S7에서 자동 채움 50몰 실페이지 대조

🌟 **쉬운 설명**
- 갤럭시 탭 S7에서 자동 채움 50몰을 모두 열었습니다. 이름·가격·사진이 페이지와 같은 몰도 있고, 가격만 다르거나 페이지 제목만 읽는 몰도 있습니다.

🔧 **기술 설명**
- 기기: `SM-T870` / `R54RB01SMVB` / Android 13. 배치 실행, `--no-uninstall`, JS probe=`2`.
- MATCH 몰: 무신사, 29CM, 반스, 나이키, 후아유, 게스, 핫핑, 낫포유, 예일, 데일리쥬(2/3), 커버낫(2/3), 필루미네이트(1/3), 인사일런스(1/3), 코드그라피, 노이아고(1, 2번은 hang), 립합, 아모멘토(1/2), 앤더슨벨, 위드윤(2/3).
- 이름·사진 맞고 가격만 다름: 미쏘, 리, 어반스터프, 파브레가, 마하그리드, 프롬비기닝. 다수는 화면가의 80~90%(회원가).
- W컨셉: 1번은 가격·사진 맞고 이름은 `[W CONCEPT]`. 2·3번은 `script_timeout`.
- 추출만 함(카탈로그 live 없음): 11번가, FILA, 하고, 룩핀, 탑텐, 무인양품, 현대Hmall, 롯데온, 유니클로, SSG, 더현대Hi, 에이블리, 지그재그, KREAM, Aritzia, 비바스튜디오, 패션플러스, 올리브영, 퀸잇, 브랜디, CJ온스타일, 4910, SSF샵, 이랜드몰.
- SSG 2번째 URL `access_blocked`. 노이아고 2140은 extract future가 끝나지 않아 세션 hang.
- 검사 뒤 debug APK `-r` 복구. 앱 uninstall 없음.

---

## 2026-08-17 - WebView 이름·가격·사진 실페이지 대조 시작

🌟 **쉬운 설명**
- 자동 채움이 되는 쇼핑몰을 대상으로, 엔진이 읽은 이름·가격·사진이 실제 상품 페이지와 같은지 비교하는 검사를 만들었습니다.

🔧 **기술 설명**
- `lib/services/live_field_compare.dart` + `integration_test/live_field_compare_test.dart`. `--no-uninstall`, `LIVE_COMPARE_MALLS`로 부분집합 가능.

---

## 2026-08-17 - 파이썬 파싱 엔진 폴더 제거

🌟 **쉬운 설명**
- 앱이 더 이상 쓰지 않는 파이썬 파싱 서버 폴더를 저장소에서 뺐습니다. 상품 읽기는 휴대폰 WebView만 사용합니다.

🔧 **기술 설명**
- `wishlist-appversion2/parsing-engine/` 삭제 (FastAPI `/parse`·`/api/scrap`, site adapters, PRICE_SCHEMA).
- 가격 규칙은 `flutter_app/lib/services/product_extract_js.dart`가 기준이다.
- 단위 테스트는 파이썬 폴더를 읽지 않음. 관리 도메인 목록 테스트 이름만 온디바이스 기준으로 바꿈.
- 리바이스 대기는 늘리지 않음.

---

## 2026-08-17 - 앱에서 파이썬 서버 연결 흔적 제거

🌟 **쉬운 설명**
- 공유 담기는 이미 휴대폰만 쓰는데, 앱 안에 남아 있던 파이썬 서버 주소와 서버 JSON 읽기 코드를 지웠습니다.
- 파이썬 엔진 폴더는 아직 저장소에 있습니다. 이번엔 앱이 그걸 부르지 못하게만 정리했습니다.

🔧 **기술 설명**
- `AppConfig.engineBaseUrl` / `lib/config.dart` 삭제. `ENGINE_BASE_URL` dart-define은 더 이상 없다.
- `ParsedProductInfo.fromEngineResponse` / `fromEngineProduct` / `fromJson` 제거. `engineUsed` 기본값은 false.
- 직접 쓰이지 않던 `http` 의존성 제거. 단위 테스트 43 passed, 대상 analyze 0 issues.
- `parsing-engine/` 폴더는 유지. 리바이스 대기는 늘리지 않음.

---

## 2026-08-17 - 갤럭시 공유 담기 WebView 경로 스모크

🌟 **쉬운 설명**
- 실물 갤럭시에서 공유 담기가 파이썬 없이 페이지를 읽는지 확인했습니다. 반스는 이름·사진·가격이 자동으로 채워졌고, ZARA는 이름·사진은 남기고 가격만 직접 넣게 했습니다.
- 위시리스트에는 상품을 저장하지 않았습니다. 검사 뒤 일반 앱을 다시 넣었습니다.

🔧 **기술 설명**
- `integration_test/share_intake_smoke_test.dart`가 공유 화면과 같은 `ParsingBridge.scrapShareInput`을 실기기 WebView 호스트로 호출한다. AppStore/Firebase 저장 없음.
- 실물 `SM-S938N` / `R3CY10LF2HE` / Android 16, SuperDisplay Stopped, `--no-uninstall`, SDK ADB 1.0.41. JS probe=`2`.
- 반스 공유 텍스트: 올드스쿨 57000, 이미지 있음, `engineUsed=false`, `needsManualPrice=false`.
- ZARA: 플리츠 쇼트 트렌치 코트, 이미지 있음, 가격 0, `price_ambiguous`, `needsManualPrice=true`. 관리 몰이라 범용 가격 우회 없음.
- 쿠팡은 관리 도메인이 아니라 페이지가 열리면 범용 추출이 허용된다. 1차 실행은 11990 자동 채움, 통과 실행은 `Access Denied`/`access_blocked`. 안정 PASS로 보지 않음.
- 원본: `wishlist-appversion2/share_intake_smoke_2026-08-17.json`.
- 검사 후 `flutter build apk --debug` + `adb install -r`. 앱/데이터 삭제 없음.

---

## 2026-08-17 - iOS blank 리셋 재확인 (오염 3쌍 + SSG/반스/Aritzia/마리떼)

🌟 **쉬운 설명**
- iOS에서 연속으로 쇼핑몰을 열어도 이전 페이지가 다음 결과에 섞이지 않는지 다시 확인했습니다. 퀸잇→브랜디, 탑텐→무인양품, 코드그라피→후아유는 모두 각자 상품이 나왔습니다.
- SSG는 여전히 접속 제한 화면입니다. 반스·마리떼는 이름·사진·가격이 같이 나왔고, Aritzia는 가격을 비운 채 두었습니다.

🔧 **기술 설명**
- 브랜치 `feat/webview-scraper-stabilize` (`eafa6b3`). 64개 전체 감사가 아니다. JS probe=`2.0`, `--no-uninstall`.
- 실물 iPhone `지으닝`은 무선으로 보였으나 `flutter test`가 wireless tether에서 앱을 시작하지 못해, 부팅된 iPhone 17 Pro 시뮬레이터(`53D6E81D-B9AC-48B0-8175-7F12FECF1041`)를 썼다.
- 오염 3쌍 모두 `finalUrl`·상품명·adapter가 요청 몰과 일치. 이전 iOS 64에서 무인양품←탑텐, 후아유←코드그라피, 퀸잇 DOM이 브랜디로 새던 오염은 이번 연속 실행에서 재현되지 않음.
- SSG `BLOCKED` `access_blocked` 「접속이 잠시 제한되었습니다」. 우회하지 않음. finalUrl `ssg.com`.
- 반스 PASS 올드스쿨 57000, `source.price=site-adapter`. 마리떼 PASS 49000, `source.price=site-adapter`.
- Aritzia `PARTIAL_NO_PRICE` `price_ambiguous`. 이름 `www.aritzia.com`, 이미지/가격 null. 전용 규칙 실패라 범용 가격 우회 없음. Android PASS·이전 iOS 64(이름·이미지 있음)와 다름.
- 원본: `wishlist-appversion2/ios_webview_recheck_2026-08-17.json`. PR #31 64몰 문서는 덮어쓰지 않음.
- 검사 후 `flutter install`로 일반 Debug를 시뮬레이터에 다시 넣었다. 이 명령이 시뮬레이터 기존 앱을 지운 뒤 설치했다. 실기기 데이터는 건드리지 않음.

---

## 2026-08-17 - 공유 담기를 WebView 전용으로 전환

🌟 **쉬운 설명**
- 상품 링크를 담을 때 더 이상 파이썬 서버를 부르지 않습니다. 휴대폰이 페이지를 직접 읽습니다.
- 가격을 못 읽어도 이름·사진·주소는 남기고, 가격만 직접 입력하면 저장됩니다.

🔧 **기술 설명**
- `ParsingBridge`의 `/parse`·`/api/scrap` HTTP 호출을 제거했다. 공유 담기는 `WebViewScraper.extract`만 사용한다.
- 추출 실패·가격 부재 시에도 URL과 읽힌 이름/이미지를 유지한다. 공유 텍스트의 제목 힌트를 상품명 후보로 쓴다.
- 저장 시 상품명·양수 가격이 없으면 막는다. 가짜 Unsplash 대표 이미지는 넣지 않는다.
- 단위 테스트: parsing_bridge / share_input / 기존 가격 의미 테스트.

---

## 2026-08-17 - WebView blank 리셋 강화와 남은 몰 전용 규칙

🌟 **쉬운 설명**
- 상품을 읽기 전에 빈 화면이 실제로 열린 뒤에만 다음 쇼핑몰을 열도록 바꿨습니다. 이전 페이지가 다음 결과에 섞이지 않게 합니다.
- 반스는 전용 상품명을 우선하고, 현대Hmall·이랜드몰 상품 주소를 상품 페이지로 인식합니다.
- 품절·단종된 감사 표본(현대Hmall, 나이키, 이랜드몰)은 현재 판매 중인 주소로 바꿨습니다. 쿠폰 예상가는 저장하지 않습니다.
- 실물 갤럭시에서 5곳을 다시 열었습니다. 현대Hmall·반스·나이키·이랜드몰은 이름·사진·가격이 같이 나왔고, 리바이스만 페이지가 끝나지 않았습니다.

🔧 **기술 설명**
- `WebViewExtractHost`는 추출마다 `about:blank` `onLoadStop`을 최대 2초 기다린 뒤에만 대상 URL을 연다. 리셋 중 콜백과 blank URL은 루프에 넘기지 않는다.
- `WebViewExtractLoop`는 blank 로드를 첫 상품 로드로 치지 않고, `finalUrl`이 요청 호스트와 다른 추출 결과는 버린다.
- 반스는 `recopick:title`을 상품명으로 우선한다. Hmall은 `itemPtc`/`slitmCd`, 이랜드몰은 `/i/item`/`itemNo`, 나이키는 `/t/` 상품 URL을 상품 페이지로 본다.
- 이랜드몰 전용 가격은 표시 판매가 `s_price`만 사용한다. `final_price`는 쿠폰 예상가라 쓰지 않는다. 관리 몰 범용 JSON-LD/OG/DOM 가격 우회는 그대로 없다.
- 감사 URL: Hmall `slitmCd=2060464676`(판매중 42900), 나이키 AF1 `IH1698-100`(BUYABLE_BUY), 이랜드몰 `itemNo=2607498077`. 기존 Hmall/나이키/이랜드 표본은 품절·404·판매종료.
- 단위 테스트 25개, 대상 analyze 0 issues.
- 실물 `SM-S938N` / `R3CY10LF2HE` / Android 16, SuperDisplay Stopped, `--no-uninstall`, SDK ADB 1.0.41. JS probe=`2`.
- 5몰 재감사 `WEBVIEW_AUDIT_ONLY=12,30,31,54,64`: 현대Hmall PASS 42900, 반스 PASS 올드스쿨 57000, 나이키 PASS 134100, 이랜드몰 PASS 55600. 리바이스는 여전히 `loading_timeout`(27.4초, 고정 대기는 늘리지 않음).
- 검사 후 일반 앱을 `flutter build apk --debug` + `adb install -r`로 복구한다.

---

## 2026-08-16 - 실기기 64개 WebView 분할 감사 완료

🌟 **쉬운 설명**
- 실물 Galaxy에서 등록 쇼핑몰 64곳을 나눠 열어 봤습니다. 이름·사진·가격이 같이 나온 곳은 46곳입니다.
- 막힌 곳, 일부러 가격을 안 적는 곳, 전용 규칙이 안 맞아 가격을 비운 곳은 통과로 세지 않았습니다.
- 검사가 끝난 뒤에는 일반 앱을 다시 넣었습니다.

🔧 **기술 설명**
- 실물 `SM-S938N` / Android 16, SuperDisplay Stopped, `--no-uninstall`, SDK ADB 1.0.41. JS probe=`2`.
- 분할: 1~3, 4~37, 38(노이아고 단독), 39~51, 52~64.
- 집계: PASS 46, EXPECTED_ABSTAIN 5(네이버·Gap·LF몰·NUGU·SHEIN), BLOCKED 2(쿠팡·H&M), PARTIAL_MEDIA 1(반스 이름), NO_RESULT 1(리바이스 `loading_timeout`), PARTIAL_NO_PRICE 9(현대Hmall·마리떼·오호라·육육걸즈·파르티멘토·Reformation·나이키·ZARA·이랜드몰).
- 11번가는 hang 없이 PASS. 노이아고는 단독 재실행에서 PASS(219000원).
- 관리 몰 전용 규칙 실패 시 범용 가격 우회 없음. iOS는 이 환경에 기기 없음.
- 검사 후 `flutter build apk --debug` + `adb install -r`로 일반 앱을 복구했습니다.

---

## 2026-08-16 - 실기기 WebView 생성·추출 복구

🌟 **쉬운 설명**
- 상품을 읽기 전에 WebView를 미리 붙여 두고, 같은 WebView를 연속으로 쓸 때 이전 쇼핑몰 페이지가 섞이지 않게 했습니다.
- 실물 Galaxy에서 1~37번까지는 실제로 페이지를 읽어 가격을 확인했습니다. 38번 이후와 iOS는 이번 실행에서 끝까지 검증하지 못했습니다.

🔧 **기술 설명**
- `WebViewExtractHost`는 `about:blank`를 항상 마운트하고 `useHybridComposition`을 켭니다. 감사 러너는 `onWebViewCreated`와 `evaluateJavascript('1+1')`이 성공할 때만 몰 감사를 시작합니다.
- 추출마다 `stopLoading` + `about:blank` 후 대상 URL을 열어, 이전 페이지 load 콜백/DOM이 다음 건을 오염시키지 않게 했습니다.
- 반스는 가격 어댑터가 이미 확인한 `recopick:title`을 상품명으로 씁니다. 관리 몰 전용 규칙 실패 시 JSON-LD/OG/DOM 가격 우회는 하지 않습니다.
- 실물 `SM-S938N` / `R3CY10LF2HE` / Android 16, SuperDisplay Stopped, SDK ADB 1.0.41. JS probe=`2`.
- 7개(`14,22,24,46,49,53,55`): 미쏘·핫핑·SSG·올리브영 PASS, 오호라·파르티멘토·Reformation은 이름/이미지만 있고 전용 가격 규칙 실패로 `price_ambiguous`.
- 1~3: 쿠팡 `BLOCKED`, 네이버 `EXPECTED_ABSTAIN`, 11번가 PASS(json-ld, hang 없음).
- 4~37: 무신사~Aritzia까지 실기기 완주. 반스 `PARTIAL_MEDIA`(이름 없음), 현대Hmall 가격 없음, 리바이스 `loading_timeout`, H&M `BLOCKED`, Gap abstain.
- 4~64는 38 노이아고에서 러너가 끊겼고, 이후 실기기 재실행은 WebView 생성 단계에서 isolate가 종료됐습니다. `flutter test` 기본 동작이 앱을 지워 `--no-uninstall`을 이후부터 사용했습니다. 패키지는 다시 `-r` 설치했습니다.
- 에뮬레이터 39~51은 JS는 동작했지만 이전 페이지 오염과 `script_timeout`이 많아 가격 통과로 보지 않습니다.
- 이 Windows 환경에는 iOS 기기가 없습니다. 대상 단위 테스트와 analyze는 통과했습니다.

---

## 2026-08-16 - WebView 추출을 위젯 트리 PlatformView로 복구

🌟 **쉬운 설명**
- 안 보이는 Headless WebView가 페이지를 열지 못하던 문제를 피하려고, 앱 안에 거의 보이지 않는 실제 WebView를 붙여 상품 페이지를 읽도록 바꿨습니다.
- 단위 테스트는 통과했지만, SuperDisplay ADB 40과 SDK ADB 41이 다시 충돌해 Android 에뮬레이터 설치가 끊겨 7개 재감사는 미검증입니다.

🔧 **기술 설명**
- `WebViewExtractHost`를 `MaterialApp`과 감사 러너에 올리고, `WebViewScraper`는 호스트가 있으면 Headless 대신 트리에 붙은 `InAppWebView`를 사용합니다.
- Headless 경로는 360×640 `setSize`를 남기되, Activity content 자식이 없으면 뷰 계층에 붙지 못하는 기존 한계를 우회하지 않고 호스트를 우선합니다.
- 대상 단위 테스트 21개와 관련 Flutter analyze 0 issues를 통과했습니다.
- Android 재감사는 `adb server version (40) doesn't match this client (41)`로 streamed install이 두 번 실패했습니다. 실물 Galaxy 앱/데이터는 삭제하지 않았고, 가짜 SDK/ADB 프록시도 만들지 않았습니다.

---

## 2026-08-16 - Flutter WebView 추출 안정화

🌟 **쉬운 설명**
- 상품 페이지가 리다이렉트나 화면 전환을 끝낸 뒤에만 가격을 읽고, 차단 화면은 바로 멈추며, 실패한 이유를 구분해서 남기도록 WebView 추출기를 바꿨습니다.
- 고정 대기 시간만 늘리지는 않았습니다. Android 에뮬레이터에서는 Headless WebView가 페이지 로드 콜백을 주지 않아 7개와 1~3번 감사를 가격 통과로 보지 않습니다.

🔧 **기술 설명**
- `webview_scraper.dart`에 시계/세션 추상화, 마지막 탐색 후 600ms 안정화, `evaluateJavascript` 4초 timeout, 명시적 `blocked` 즉시 종료, 빈 결과 1회 reload, 가격 fingerprint 2회 연속 확인, 실패 이유(`loading_timeout`, `script_timeout`, `access_blocked`, `network_error`, `not_product_page`, `price_ambiguous`, `unsupported_currency`)를 추가했습니다.
- 대상 단위 테스트 20개와 관련 Flutter analyze 0 issues를 통과했습니다.
- Pixel 10 / Android 17 에뮬레이터(`emulator-5554`)에서 SuperDisplay는 떠 있지 않았고 SDK ADB 1.0.41만 사용했습니다. 첫 설치는 ADB daemon 5037 연결 실패로 한 번 끊겼고, 재시도 후 `WEBVIEW_AUDIT_ONLY=14,22,24,46,49,53,55`와 `WEBVIEW_AUDIT_START=0 END=3`을 실행했습니다. 두 실행 모두 상품 내용 없이 `loading_timeout`만 나와 가격 추출 성공으로 보지 않습니다. 4~64 전체 감사는 같은 인프라 실패를 반복할 뿐이라 실행하지 않았습니다. 실물 기기 앱/데이터는 삭제하지 않았습니다.

---

## 2026-08-16 - Android WebView 이미지·가격 안전성 보정

🌟 **쉬운 설명**
- 깨진 대표 이미지 주소를 앱에서 자동으로 정상화하고, ZARA처럼 전용 규칙이 확인되지 않은 관리 쇼핑몰은 화면 숫자를 임의 가격으로 저장하지 않게 했습니다.
- 오래된 품절 감사 상품을 현재 판매 상품으로 바꾸고 룩핀·낫포유 등 실제 Android 누락 원인을 보완했습니다.

🔧 **기술 설명**
- 이미지 URL의 중복 스킴(`https:https://`), HTML entity(`&amp;`), 상대경로, HTTPS 페이지의 HTTP 이미지를 정규화합니다.
- 룩핀과 오호라는 페이지 전체의 추천상품/숨김 UI에 있는 `품절·재입고` 문구 대신 주상품의 활성 구매 동작만 사용합니다. 낫포유는 JSON-LD에 availability가 없을 때 판매 옵션, 표시 판매가, `product_price`, Product offer가 모두 일치해야만 확정합니다.
- 미쏘 구매 버튼 문구, 파르티멘토의 밑줄 상품명, 핫핑 옵션별 24,800~25,800원 범위를 현재 렌더링 구조에 맞췄습니다. SSG·올리브영의 한국어 접근 제한 화면은 `BLOCKED`로 분류합니다.
- Android 17 에뮬레이터 64개 1차 재감사는 PASS 43, 가격은 확인됐으나 이름 누락 1, 의도적 abstain 5, 가격 없음 8, 완전 결과 없음 4, 접근 차단 2, timeout 1이었습니다. 이 실행에서 룩핀·무인양품·리·낫포유·인사일런스·게스·Aritzia가 새 판매 표본으로 정상 통과했고 ZARA provisional 가격은 제거됐습니다.
- 이후 미쏘·핫핑·오호라·파르티멘토·Reformation 표본/규칙과 SSG·올리브영 차단 분류를 보완했습니다. 대상 단위 테스트 7개와 정적 분석(0 issues)은 통과했지만, 마지막 Android 7건 재실행은 SuperDisplay ADB 40이 SDK ADB 41 서버를 반복 교체해 설치 스트림이 끊겨 완료하지 못했습니다. 이 7건은 Android 통과로 보고하지 않습니다.
- 로그인·결제·실물 기기 앱 삭제는 하지 않았습니다.

---

## 2026-08-16 - Android WebView 64개 쇼핑몰 대표 상품 감사

🌟 **쉬운 설명**
- Python 서버를 사용하지 않고 Pixel 10 Android 에뮬레이터에서 등록 쇼핑몰 64곳을 한 건씩 직접 열어 상품명·이미지·가격 추출 여부를 확인했습니다.
- 37곳은 쇼핑몰 전용 규칙으로 조건 없는 구매 가격까지 확정했고, Gap·LF몰·NUGU·SHEIN·네이버 쇼핑 5곳은 설계대로 잘못된 양수 가격을 만들지 않았습니다.
- 나머지는 접근 차단, 판매 종료 표본, 최신 페이지 구조와 규칙 불일치로 확인되어 WebView 규칙 보정과 판매 중 URL 재검증이 필요합니다.

🔧 **기술 설명**
- `integration_test/webview_all_malls_audit_test.dart`에 서버를 거치지 않는 64개 URL 배치 러너, 쇼핑몰별 45초 격리 제한, JSON line 결과 출력을 추가했습니다.
- Android 17/API 37 에뮬레이터 결과는 confirmed 37, expected abstain 5, provisional 1, partial-no-price 14, no-result 4, blocked 2, timeout 1입니다.
- 쿠팡과 H&M은 Access Denied, 11번가는 네이티브 WebView timeout, SSG는 접속 제한 화면이었습니다. ZARA는 숫자를 얻었지만 전용 규칙이 아닌 provisional 폴백이어서 confirmed로 세지 않았습니다.
- 이미지 결과는 정상 HTTPS 45, 누락 11, 중복 스킴 3, HTML entity가 남은 쿼리 2, HTTP 2, 상대 경로 1입니다. 결과 원본은 `0.EngineTest/data/webview_android_audit_64_2026-08-16.json`에 기록했습니다.
- 로그인·결제·장바구니 변경은 하지 않았습니다. Galaxy 실물 기기 실행은 PC의 구형/신형 ADB 충돌로 시작되지 않아 이번 수치에 포함하지 않았습니다.

---

## 2026-08-17 - iOS 공유 시트에 wishkit 노출

🌟 **쉬운 설명**
- 아이폰에서 사파리·카톡·쇼핑몰 앱의 공유 목록에 wishkit이 보이도록 했습니다.
- 상품 URL을 공유하면 기존과 같이 공유 담기 화면으로 이동합니다. Android 동작은 그대로입니다.

🔧 **기술 설명**
- iOS `Share Extension` 타깃을 추가하고 Runner와 `group.com.softstudio.wishlist` App Group으로 공유 텍스트를 넘깁니다.
- Extension은 URL·텍스트·이미지를 App Group에 저장한 뒤 `ShareMedia-com.softstudio.wishlist` 스킴으로 호스트 앱을 엽니다.
- 호스트 앱은 Android와 같은 `com.softstudio.wishlist/share` MethodChannel로 공유 문장을 Flutter `/share` 화면에 전달합니다.
- 공유 시트 표시 이름은 `wishkit`이며, 텍스트·웹 URL·웹페이지·이미지를 활성화 규칙에 포함합니다.

---

## 2026-08-17 - 살까말까 링크 공유 HTML 페이지

🌟 **쉬운 설명**
- 살까말까를 링크로 보내면, 앱 속 바구니 화면과 비슷한 웹 페이지가 만들어지고 그 주소가 복사됩니다.
- 로그인하지 않은 친구도 브라우저에서 상품 목록을 볼 수 있고, 28일이 지나면 페이지는 자동으로 사라집니다.

🔧 **기술 설명**
- 링크 복사 시 바구니 스냅샷 HTML을 Firebase Storage `share-pages/{uid}/{pageId}.html`에 올리고, 만료 시각은 Firestore `sharePages`에 기록합니다.
- 상품명·URL은 HTML 이스케이프와 http(s) 검사로 넣고, 같은 바구니를 다시 공유하면 같은 페이지를 덮어쓰며 28일 타이머를 다시 시작합니다.
- Cloud Functions `cleanupExpiredSharePages`가 매일 03:00(KST)에 만료된 Storage 파일과 메타 문서를 삭제합니다.

---

## 2026-08-16 - 패션 플랫폼 선택 확장 9곳

🌟 **쉬운 설명**
- 퀸잇, 브랜디, 4910, CJ온스타일, SSF샵, 이랜드몰, ZARA, NUGU, SHEIN을 URL 인식과 가격 안전 관리 대상에 추가했습니다.
- 조건 없는 가격을 확인한 7곳은 전용 규칙을 추가했고, 일본 엔화 전용 NUGU와 세션 혜택이 복잡한 SHEIN은 잘못된 원화 가격을 만들지 않도록 차단했습니다.

🔧 **기술 설명**
- Python과 Flutter WebView에 Queenit Next state, Brandi `prefetch-data`, 4910 goods state, CJ/SSF Product offer, Eland 가격·재고 변수, ZARA `analyticsData.mainPrice` 교차 검증을 동기화했습니다.
- ZARA JSON-LD의 1/100 KRW 값은 현재 상품 `mainPrice`, ProductGroup ID, live variant가 모두 일치할 때만 ×100 합니다.
- 쿠폰·첫구매·카드·멤버십·최대혜택 가격, 품절·종료·목록/모코드·추천상품·내부 필드 충돌을 거부하는 회귀 테스트를 추가했습니다.
- 관리 HTML 쇼핑몰은 61개(confirmed 57, guard-only 4), 전체 URL 레지스트리는 64개가 되었습니다. 로그인·결제·장바구니 변경은 하지 않았습니다.

---

## 2026-08-16 - 전체 서버 회귀·실네트워크 및 Android 실기기 검증

🌟 **쉬운 설명**
- Python 파싱 엔진의 API 포함 전체 테스트와 실제 네트워크 테스트를 모두 통과했습니다.
- 최신 디버그 APK를 연결된 Android 실기기에 기존 앱 데이터를 유지한 채 설치하고 정상 실행을 확인했습니다.

🔧 **기술 설명**
- Windows Python 3.11과 프로젝트 전체 의존성(`lxml`, FastAPI 포함)으로 비통합 테스트 261개, 실네트워크 통합 테스트 2개가 통과했습니다.
- 실제 `lxml`이 닫는 `html` 태그 뒤의 노드를 버리는 차이 때문에 에이블리의 충돌 메타 차단 테스트가 실패하던 문제를 수정했습니다. 에이블리의 보안상 중요한 상품 메타 유일성 검사는 불완전한 HTML도 보존하는 `html.parser`로 별도 확인합니다.
- `app-debug.apk`를 SM-S938N(Android 16)에 `adb install -r`로 설치했으며, `com.softstudio.wishlist` 프로세스 실행을 확인했습니다.

---

## 2026-08-16 - Flutter 회귀 안정화 및 Android 빌드 검증

🌟 **쉬운 설명**
- 가격 규칙 전체 동기화 이후 남아 있던 Flutter 테스트 실패와 deprecated 경고를 정리했습니다.
- 전체 테스트와 정적 분석을 통과하고 Android 디버그 APK 생성까지 확인했습니다.

🔧 **기술 설명**
- `AppStore`에 테스트용 Firebase 구성 주입점을 추가해 실제 Firebase 설정이나 남은 인증 세션에 영향을 받지 않는 회귀 테스트로 변경했습니다.
- `ReorderableListView.onReorder`를 `onReorderItem`으로 이전하고, 새 API가 이미 보정한 목적지 인덱스에 맞게 탭 재정렬 로직을 수정했습니다.
- Flutter analyze는 0 issues, 전체 Flutter 테스트는 19 passed입니다. `flutter build apk --debug`도 성공했습니다.

---

## 2026-08-16 - Flutter 온디바이스 가격 규칙 전체 동기화 완료

🌟 **쉬운 설명**
- Python에서 검증된 쇼핑몰별 HTML 가격 규칙 52개를 Flutter 앱 내부 WebView 추출기에 모두 반영했습니다.
- 쿠폰·회원가·카드가·적립금·배송비·추천상품·품절 옵션은 구매 가격에서 제외하고, 여러 후보가 충돌하면 가격을 비웁니다.
- Gap과 LF몰은 기존 조사 결론대로 잘못된 양수 가격을 만들지 않는 guard-only 상태를 유지합니다.

🔧 **기술 설명**
- 공통 Cafe24 offer/meta-sale 규칙과 롯데온·유니클로·SSG·더현대·에이블리·지그재그·크림·H&M·Aritzia·Reformation·Nike·Oliveyoung 등의 전용 렌더링 규칙을 이식했습니다.
- URL 레지스트리/서버 디스패처의 52개 플랫폼과 WebView 관리 도메인의 자동 대조 결과 누락은 0개입니다.
- 관리 도메인은 전용 규칙 실패 시 JSON-LD·OG·범용 DOM 가격으로 우회하지 않으며, option-dependent 최소·최대 범위와 가격 evidence를 앱 모델까지 보존합니다.
- JavaScript 구문 검사와 동기화/가격 모델 대상 테스트 10개가 통과했습니다. 전체 Flutter 테스트는 17개 통과, 기존 Firebase 미사용 로그인 상태 테스트 1개가 실패했습니다. analyze는 기존 deprecated `onReorder` 안내 1건만 남았습니다.

---

## 2026-08-16 - Flutter 온디바이스 가격 규칙 동기화 1차 (9개 쇼핑몰)

🌟 **쉬운 설명**
- 무신사, W컨셉, 29CM, FILA, 하고, 룩핀, 탑텐, 무인양품, 현대Hmall의 검증된 가격 의미 규칙을 앱 내부 WebView 추출기로 옮겼습니다.
- 이 쇼핑몰들은 전용 규칙의 가격·재고 조건이 맞지 않으면 범용 화면 숫자로 대신 채우지 않습니다.
- 옵션별 가격이 다른 상품은 최소·최대 가격과 옵션 의존 상태를 앱 모델까지 전달합니다.

🔧 **기술 설명**
- `product_extract_js.dart`에 Python 어댑터와 같은 필드 교차 검증 및 충돌 시 abstain 규칙을 추가했습니다.
- WebView 결과에 `purchasePriceStatus`, `priceConfidence`, `availability`, 옵션 가격 범위와 evidence를 추가하고 `ParsedProductInfo`까지 보존합니다.
- 검증되지 않은 범용 DOM 가격은 계속 provisional/low이며, 9개 관리 대상 사이트는 전용 규칙 실패 시 가격을 null로 유지합니다.
- JavaScript 구문 검사와 Flutter 가격 모델/WebView 결과 대상 테스트 7개가 통과했습니다. 전체 Flutter 테스트는 14개 통과, 기존 `widget_test.dart`의 Firebase 미사용 로그인 상태 기대값 1개가 실패했습니다. analyze는 기존 deprecated `onReorder` 안내 1건만 남았습니다.

---

## 2026-08-16 - 남은 Tier 1 쇼핑몰 검증 (쿠팡·11번가·네이버)

🌟 **쉬운 설명**
- URL 레지스트리에 남아 있던 쿠팡·11번가·네이버까지 조사해 등록 쇼핑몰 55개의 1차 검토를 마쳤습니다.
- 쿠팡은 같은 상품 번호 안에서도 수량·옵션별 가격이 달라 정확한 선택 옵션 번호까지 맞지 않으면 가격을 저장하지 않습니다.
- 11번가는 최대할인가·쿠폰·옵션 범위를 단일 판매가로 오인하지 않고, 종료된 네이버 쇼핑 검색 API는 운영 호출에서 제외했습니다.

🔧 **기술 설명**
- Tier 1 후보 매칭은 동일 productId의 가격·상품이 충돌하거나 제목 유사도 1·2위가 근접하면 abstain합니다.
- 쿠팡 공유 URL의 `itemId/vendorItemId`를 API `productUrl`과 교차 검증하고 `productId`만 같은 다른 수량 옵션은 거부합니다.
- 11번가 ProductInfo는 요청 `ProductCode`와 정확히 일치하는 유일한 상품만 허용합니다. `Product.SalePrice`는 장바구니·실 API 검증 전까지 provisional입니다.
- 네이버 `hprice`는 할인 전 정가가 아니라 최고가이므로 regular_price로 저장하지 않으며, 2026-07-31 종료된 쇼핑 검색 어댑터는 기본 운영 디스패처에서 제거했습니다.
- 공개 페이지 6건(쿠팡 3, 11번가 3)을 확인했고 네이버 접근 제한은 우회하지 않았습니다. 로그인·결제·장바구니 변경은 하지 않았습니다.
- Tier 1·파이프라인·URL 대상 테스트 105개와 API 서버·실네트워크를 제외한 회귀 테스트 258개가 통과했습니다(실네트워크 2개 deselected). API 서버 테스트와 실제 자격 증명 API 호출은 실행하지 않았습니다.

---

## 2026-08-16 - URL 등록 쇼핑몰 확대 검증 (나이키·올리브영)

🌟 **쉬운 설명**
- 기존 URL 식별만 있던 나이키와 올리브영의 현재 판매 상품을 각각 3개씩 조사하고 가격 의미 규칙을 추가했습니다.
- 나이키는 선택한 색상의 정가·자동 판매가만 사용하고, 올리브영은 화면 최적가에 포함된 쿠폰을 빼고 자동 세일 가격만 저장합니다.
- 품절 옵션, 다른 색상·추천상품, 쿠폰·카드·포인트·배송비 숫자는 구매 가격으로 잘못 선택하지 않습니다.

🔧 **기술 설명**
- 나이키는 OG URL의 `styleColor`를 `__NEXT_DATA__.productGroups[].products`와 연결하고 `BUYABLE_BUY`, KRW `currentPrice/initialPrice`, 해당 스타일의 size offer 가격을 교차 검증합니다. 비로그인 장바구니는 사이트 자동화 차단으로 확인하지 못해 confidence는 medium입니다.
- 올리브영은 Next.js flight-data의 단일 상품과 판매 옵션 상태를 읽고, 쿠폰 포함 `finalPrice` 대신 `maxBenefitPriceDto.promotionSalePrice`를 구매가로 사용합니다. 쿠폰이 섞인 복수 옵션의 무조건 가격을 안전하게 계산할 수 없으면 abstain합니다.
- 쇼핑몰별 HTML 가격 어댑터는 52개로 늘었고 confirmed 50개, guard-only Gap·LF몰 2개입니다. 별도 Tier 1/API 대상은 쿠팡·네이버·11번가입니다.
- 가격·URL 대상 테스트 196개와 API·실네트워크 제외 회귀 테스트 249개가 통과했습니다(실네트워크 2개 deselected). API 서버 테스트는 실행하지 않았습니다.

---

## 2026-08-16 - 50개 쇼핑몰 가격 의미 조사 완료 (Aritzia·Gap·LF몰)

🌟 **쉬운 설명**
- Aritzia의 종료 상품을 현재 판매 중인 원화 상품 3개로 교체하고, 옵션과 비로그인 장바구니 가격까지 확인해 양수 규칙을 추가했습니다.
- Gap은 장바구니에서 40% 자동 할인이 적용되는 실제 상품 가격을 확인했지만, 달러 소수 가격을 현재 원화 정수 모델에 잘못 저장하지 않도록 안전 차단을 유지합니다.
- LF몰은 렌더링 후 상품 가격과 옵션 범위를 확인했지만 Python 정적 HTML에는 재고가 없어, 잘못된 품절·추천상품 가격을 확정하지 않도록 안전 차단을 유지합니다.

🔧 **기술 설명**
- Aritzia는 `#mobify-data`의 단일 주상품, URL 선택 색상, `variants[].orderable/maxOrderQuantity`와 현지화된 `product-list-price/sale-text`, Add to Bag 원화 가격을 교차 검증합니다.
- stale GBP/OutOfStock JSON-LD, 전 옵션 품절, 1,000원 미만의 깨진 현지화 값, 복수 주상품 상태는 abstain합니다.
- Gap guest cart의 USD 39.95 → USD 23.97 자동 할인을 검증했지만 통화·소수 모델이 없어 환율 또는 센트 단위를 추측하지 않습니다.
- LF몰의 일반 상품 95,000원/247,500원과 43개 옵션 상품 36,430~54,650원을 확인했지만, 정적 fetch에 옵션 재고가 없으므로 후속 렌더링/API 지원 전까지 JSON-LD 단독 값을 확정하지 않습니다.
- 50개 쇼핑몰 조사를 모두 마쳤고 누적 confirmed는 48/50, guard-only는 Gap·LF몰 2개입니다. 가격·URL 대상 테스트 191개, API·실네트워크 제외 회귀 테스트 244개가 통과했습니다(실네트워크 2개 deselected).

---

## 2026-08-16 - 쇼핑몰별 가격 의미 규칙 10차 확대 (9개 쇼핑몰)

🌟 **쉬운 설명**
- 미쏘, 리(Lee), 위드윤, 육육걸즈, 파르티멘토, 패션플러스, 프롬비기닝, Reformation의 판매 중 상품 가격 규칙을 추가했습니다.
- 쿠폰·회원·신규회원·카드·적립금·배송비는 일반 구매 가격에서 제외하고, 패션플러스 묶음상품은 실제 판매 옵션의 최소~최대 가격을 반환합니다.
- LF몰은 주상품 화면이 로딩되지 않고 JSON-LD에 재고가 없어 숫자를 확정하지 않는 안전 규칙을 적용했습니다.

🔧 **기술 설명**
- Cafe24 계열은 주상품 ID, KRW 정가/자동 판매가 meta, 명시적 InStock option과 화면 구매 동작을 교차 검증합니다. 미쏘의 긴/짧은 중복 Product 이름은 포함 관계일 때만 같은 주상품으로 인정합니다.
- 패션플러스는 단일 Product의 `offers.sale_price`와 활성 `button.btn_option` 가격을 교차 검증하고, 대표 비교가가 최고 옵션가보다 낮은 묶음에서는 regular_price를 비웁니다.
- Reformation은 localized KRW/InStock offer만 사용하며 비로그인 장바구니 상품행·subtotal까지 대조했습니다. LF몰은 availability 없는 JSON-LD 단독 가격을 차단합니다.
- 7개 신규 URL 규칙과 양수·품절·쿠폰·옵션 범위·복수 주상품·통화 충돌 회귀 테스트를 추가했습니다.
- 누적 confirmed는 47/50, guard-only는 Gap·Aritzia·LF몰 3개입니다. 가격·URL 대상 테스트 189개, API·실네트워크 제외 회귀 테스트 242개가 통과했습니다(실네트워크 2개 deselected).

---

## 2026-08-16 - 쇼핑몰별 가격 의미 규칙 9차 확대 (9개 쇼핑몰)

🌟 **쉬운 설명**
- 노이아고, 립합, 마리떼, 마하그리드, 비바스튜디오, 아모멘토, 앤더슨벨, 예일, 오호라 상품 27개의 가격과 판매 옵션을 확인했습니다.
- 신규회원·카카오 채널·멤버십·수량 조건 쿠폰과 적립금은 일반 구매 가격에서 제외했습니다.
- 화면에 할인 가격이 남아 있어도 전 옵션 품절이거나 재고 의미가 빠진 상품은 가격을 확정하지 않습니다.

🔧 **기술 설명**
- Cafe24 `product:sale_price:amount`를 주상품 ID, 원화, Product의 명시적 InStock 옵션 및 화면 가격과 교차 검증하는 공통 규칙을 추가했습니다.
- 쇼핑몰에 따라 Product offer가 판매가 또는 할인 전 가격을 담는 차이를 허용하되, 어느 쪽과도 일치하지 않으면 abstain합니다.
- 마하그리드는 활성 장바구니/구매 버튼을, 오호라는 선택된 주상품 총액을 추가로 요구합니다.
- 예일의 할인 전 가격은 명시적 `#span_product_price_custom`에서만 regular_price로 사용합니다.
- 9개 쇼핑몰 URL 규칙과 품절·메타 충돌·복수 주상품 회귀 테스트를 추가했습니다.
- 누적 confirmed는 39/50이며 가격·URL 대상 테스트 163개, API·실네트워크 제외 회귀 테스트 216개가 통과했습니다(실네트워크 2개 deselected).

---

## 2026-08-16 - 쇼핑몰별 가격 의미 규칙 8차 확대 (9개 쇼핑몰)

🌟 **쉬운 설명**
- 게스, 리바이스, 반스, 커버낫, 코드그라피, 후아유, H&M의 조건 없는 구매 가격 규칙을 추가했습니다.
- 쿠폰·신규회원·간편결제·회원 프로모션 가격은 제외하고 실제 판매 가능한 옵션의 기본 상품 가격만 사용합니다.
- Gap은 달러 가격과 결제단계 할인이 섞이고, Aritzia는 원화 화면과 GBP/품절 내부 데이터가 충돌하여 잘못된 확정값 대신 안전하게 가격을 비웁니다.

🔧 **기술 설명**
- 게스·리바이스·반스는 각각 Product offer/화면/스크립트, Shopify live variant, `recopick` 메타와 활성 사이즈를 교차 검증합니다.
- 커버낫·코드그라피·후아유는 Cafe24 주상품 ID, KRW sale meta, InStock offers, 본 가격 영역이 일치할 때만 확정합니다.
- H&M은 canonical article에 연결된 ProductGroup의 KRW/InStock variant만 사용하며, Gap·Aritzia에는 비원화·충돌 가격 차단 규칙을 적용했습니다.
- 9개 쇼핑몰의 URL 식별과 양수·품절·통화·쿠폰·복수 주상품·충돌 회귀 테스트를 추가했습니다.
- 누적 confirmed는 30/50이며 Gap·Aritzia를 포함한 guard-only는 4개입니다.
- 가격·URL 대상 테스트 137개, API·실네트워크 테스트를 제외한 Python 테스트 190개가 통과했습니다(실네트워크 2개 deselected).

---

## 2026-08-16 - 쇼핑몰별 가격 의미 규칙 7차 확대

🌟 **쉬운 설명**
- 에이블리, 지그재그, 크림 상품 9개의 화면 가격·옵션·구매 가능 상태를 확인했습니다.
- 에이블리의 적립·페이백, 지그재그의 첫구매쿠폰가, 크림의 최대 혜택가를 일반 구매 가격에서 제외했습니다.
- 크림은 고정가 브랜드배송만 확정하고, 사이즈별 시세를 로그인 없이 확인할 수 없는 거래 상품은 가격을 확정하지 않습니다.

🔧 **기술 설명**
- 에이블리는 주상품 ID·KRW·재고 메타와 화면의 `나의 예상 구매가/즉시 할인`을 교차 검증합니다.
- 지그재그는 `display_final_price.final_price.price`를 구매 가격으로 사용하고, 조건부 `final_price_additional` 및 OG 첫구매쿠폰가는 제외합니다.
- 크림은 Product JSON-LD와 `브랜드배송` 고정가를 교차 검증하고 입찰·옵션 시세형 상품은 abstain합니다.
- 크림 URL 상품 ID 규칙과 세 쇼핑몰의 양수·품절·쿠폰·충돌 회귀 테스트를 추가했습니다.
- 가격·URL 대상 테스트 112개, API·실네트워크 테스트를 제외한 Python 테스트 165개가 통과했습니다(실네트워크 2개 deselected).

---

## 2026-08-15 - 쇼핑몰별 가격 의미 규칙 6차 확대

🌟 **쉬운 설명**
- 유니클로, SSG, 더현대Hi 상품 9개의 화면 가격·옵션·구매 가능 상태를 다시 확인했습니다.
- SSG의 카드혜택가와 배송비, 더현대Hi의 카드 즉시할인·임직원 전용 상품을 일반 구매 가격에서 제외했습니다.
- 유니클로는 판매 중인 옵션의 가격만 사용하고, 품절 옵션이나 원화가 아닌 해외 상품 가격은 확정하지 않습니다.

🔧 **기술 설명**
- 유니클로는 단일 ProductGroup의 hasVariant offers 중 KRW/InStock 가격만 사용하며 옵션 가격 차이가 있으면 범위를 반환합니다.
- SSG는 판매 가능 상태의 resultItemObj.bestAmt를 구매 가격, sellprc를 비교 가격으로 사용하고 preCpnDcPrc 일치·cpnYn=N을 요구합니다.
- 더현대Hi는 prcInfo.dcPrc/sellPrc, sellPossQty, ostkYn, sellMdaPossYn을 교차 검증하고 폐쇄몰·임직원 상품을 차단합니다.
- 가격·URL 대상 테스트 104개, API·실네트워크 테스트를 제외한 Python 테스트 157개가 통과했습니다.

---

## 2026-08-14 - 쇼핑몰별 가격 의미 규칙 5차 확대

🌟 **쉬운 설명**
- 인사일런스, 파브레가, 핫핑의 상품 페이지와 옵션 가격을 다시 확인했습니다.
- 핫핑의 쿠폰 적용가는 제외하고, 실제 비로그인 장바구니에 담기는 옵션 가격을 사용합니다.
- 품절 옵션, 깨진 상품 페이지, 상품이 아닌 에디토리얼·목록 페이지의 숫자는 가격으로 확정하지 않습니다.

🔧 **기술 설명**
- 세 쇼핑몰의 URL 식별 규칙과 전용 가격 어댑터를 추가했습니다.
- 인사일런스는 `product_price`와 Product offer가 일치하고 실제 판매 옵션이 있을 때만 확정합니다.
- 파브레가는 Product offer의 정가와 `product_sale_price` 또는 화면 자동 할인 판매가를 분리합니다.
- 핫핑은 명시적 `InStock` 옵션들의 최소·최대 가격을 사용하고 `쿠폰적용가`는 읽지 않습니다.
- 가격·URL 대상 테스트 95개, API·실네트워크 테스트를 제외한 Python 테스트 148개가 통과했습니다.

---

## 2026-08-14 - 쇼핑몰별 가격 의미 규칙 4차 확대

🌟 **쉬운 설명**
- 필루미네이트, 어반스터프, 낫포유 상품 9개의 정가·판매가 의미를 다시 확인했습니다.
- 필루미네이트의 구조화 데이터가 할인 전 가격을 판매가처럼 제공하는 문제를 바로잡았습니다.
- 어반스터프처럼 장바구니 다음 비회원 주문서에서 자동 할인이 적용되는 경우도 조건 없는 구매 가격에 반영합니다.
- 낫포유의 배송비와 0원 테스트 페이지는 상품 구매 가격에서 제외합니다.

🔧 **기술 설명**
- 세 쇼핑몰의 URL 식별 규칙과 전용 가격 어댑터를 추가했습니다.
- 필루미네이트는 `product_price/product_sale_price`를 재고가 있는 Product 옵션과 교차 검증합니다.
- 어반스터프는 Product offer 정가와 자동 할인 판매가를 함께 사용하고, 재고 정보가 빠진 경우 실제 옵션과 담기 버튼을 요구합니다.
- 낫포유는 `소비자가/판매가` 레이블과 Product offer 가격이 일치할 때만 확정합니다.
- 가격·URL 대상 테스트 84개, API 테스트를 제외한 비네트워크 Python 테스트 137개가 통과했습니다.

---

## 2026-08-14 - Cafe24 가격·재고 안전 규칙 확대

🌟 **쉬운 설명**
- 데일리쥬 상품의 옵션 가격과 비로그인 장바구니 가격을 대조했습니다.
- 미쏘의 품절 상품 가격과 Lee 행사 페이지의 99,999원을 실제 구매 가격으로 잘못 보여주지 않게 했습니다.
- 옵션마다 가격이 다른 Cafe24 상품은 하나의 임의 가격 대신 최소·최대 범위를 표시합니다.

🔧 **기술 설명**
- Cafe24 Product JSON-LD에서 재고 상태가 명시된 옵션만 가격 후보로 사용합니다.
- 모든 옵션이 `OutOfStock`이거나 availability가 없는 콘텐츠 페이지는 확정 가격을 반환하지 않습니다.
- 미쏘·데일리쥬·Lee URL 식별 규칙과 회귀 테스트를 추가했습니다.
- 비네트워크 Python 테스트 130개가 통과했습니다.

---

## 2026-08-14 - 쇼핑몰별 가격 의미 규칙 3차 확대

🌟 **쉬운 설명**
- 무인양품, 현대Hmall, 롯데온의 상품 페이지·옵션·장바구니 흐름을 확인했습니다.
- 무인양품은 배송비를 상품 가격과 분리하고, Hmall은 표시 판매가격과 실제 혜택가를 구분합니다.
- 롯데온처럼 내부 데이터와 실제 화면의 가격·품절 상태가 충돌하면 잘못된 가격을 보여주지 않습니다.

🔧 **기술 설명**
- 무인양품은 주상품의 `sale_state`, `retail_price`, `sell_price`, `last_price`가 안전하게 일치할 때만 확정합니다.
- Hmall은 `itemPtc.bbprc`를 구매 가격, `sellPrc`를 비교 가격으로 사용하고 `soldout=false`를 요구합니다.
- 롯데온은 Product JSON-LD의 InStock offer 가격이 실제 화면 판매가와 일치하고 품절 문구가 없을 때만 확정합니다.
- 세 쇼핑몰의 URL 식별 규칙과 회귀 테스트를 추가했으며, 비네트워크 Python 테스트 120개가 통과했습니다.

---

## 2026-08-14 - 쇼핑몰별 가격 의미 규칙 2차 확대

🌟 **쉬운 설명**
- 하고, 룩핀, 탑텐 상품 9개를 대상으로 페이지 가격의 뜻을 다시 확인했습니다.
- 하고의 쿠폰 예상가와 룩핀의 적립금을 실제 구매 가격으로 잘못 읽던 문제를 막았습니다.
- 품절·구매 불가·종료 상품처럼 실제로 살 수 없는 페이지는 가격이 보여도 확정값을 내지 않습니다.

🔧 **기술 설명**
- 하고는 `goodsInfo.sellPrice/dcPrice`를 조건 없는 구매 가격, `goodsInfo.price`를 정가로 사용하고 쿠폰 표시가는 제외합니다.
- 룩핀은 상품 본 가격 영역의 판매가와 취소선 정가만 읽고 적립금 범위는 제외합니다.
- 탑텐은 유효한 Product JSON-LD의 offer 가격과 `정가` 추가 속성을 사용하며 빈 `OutOfStock` 페이지에는 응답하지 않습니다.
- URL 정규화 규칙과 어댑터 단위 테스트를 추가했고, 비네트워크 Python 테스트 109개가 통과했습니다.

---

## 2026-08-14 - 쇼핑몰별 가격 의미 규칙 1차 확대

🌟 **쉬운 설명**
- 무신사에 이어 W컨셉, 29CM, FILA의 가격 의미를 실제 옵션 선택과 비로그인 장바구니 흐름으로 확인했습니다.
- 쿠폰·신규회원·카카오 채널 혜택은 조건 없는 구매 가격에서 제외합니다.
- 옵션마다 가격이 다르면 `option_dependent`와 최소·최대 가격으로 표시합니다.

🔧 **기술 설명**
- W컨셉은 `GA4ItemObj.SalePrice/CustomerPrice`를 주문 폼 가격과 교차 검증합니다.
- 29CM은 `item.sellPrice/consumerPrice`를 사용하고 표시 쿠폰 가격은 제외합니다.
- FILA는 variant offer 가격을 사용하고 선택 variant의 `compare_at_price`만 정가 근거로 인정합니다.
- 내부 근거가 불일치하면 확정하지 않고 기존 provisional 경로로 돌아갑니다.
- 비네트워크 Python 테스트 96개와 Flutter 가격 테스트 및 정적 분석을 통과했습니다.

---

이 문서는 최초 공유본 대비 **무엇을 왜 바꿨는지**를 기록합니다.
각 항목은 두 가지 설명을 함께 답니다:

- 🟢 **쉬운 설명** — 코드를 안 봐도 이해되는 설명 (팀 공유·발표용)
- 🔧 **기술 설명** — 파일·구체적 변경 (구현 확인용)

> 앞으로 코드가 바뀔 때마다 이 문서 맨 위에 같은 형식으로 계속 추가합니다.

## 2026-08-14 — 가격 JSON 의미 정의 v2

🟢 **쉬운 설명**
- 정가와 조건 없는 구매 가격을 서로 다른 값으로 정의했습니다. 한쪽만 알아도 다른 쪽을 억지로 채우지 않습니다.
- 엔진이 숫자를 찾았더라도 그 의미가 확실하지 않으면 `확정`이 아니라 `임시 후보`로 알려줍니다.
- 쿠폰·회원·카드·포인트·배송비는 조건 없는 구매 가격에서 제외합니다.

🔧 **기술 설명**
- 응답에 `schema_version: 2`와 canonical `pricing` 객체를 추가했습니다.
- `purchase_price_status`, `confidence`, 옵션 가격 범위, 근거 필드를 추가했습니다.
- 기존 `price/original_price`는 이전 앱과 저장 데이터의 호환용 별칭으로 유지합니다.
- Flutter 모델은 `pricing`을 우선 읽으며, canonical 값이 `null`이면 오래된 호환 필드로 되살리지 않습니다.
- 첫 쇼핑몰별 어댑터로 무신사를 추가했습니다. `goodsPrice.salePrice`를 조건 없는 구매 가격,
  `goodsPrice.normalPrice`를 정가로 확정하고 `couponPrice/finalPrice`는 제외합니다.
- 서로 다른 무신사 가격 객체가 한 페이지에 섞이거나 알 수 없는 가격 유형이면 확정하지 않고 범용 추정으로 폴백합니다.
- 상세한 필드 정의와 표시 규칙은 `parsing-engine/server/PRICE_SCHEMA.md`에 기록했습니다.

---

## 2026-08-13 - 50개 쇼핑몰 가격 엔진 점검

🟢 **쉬운 설명**
- 상품 상세 페이지만 대상으로 50개 쇼핑몰에서 서로 다른 상품 3개씩, 총 150개를 검사했습니다.
- 검색·카테고리·로그인 화면이나 같은 상품의 다른 탭은 상품으로 세지 않게 검사 기준을 강화했습니다.
- 쿠폰·회원·카드 가격은 제외하고 정가와 공개 판매가만 저장하며, 원화 5,000원 미만의 비정상 후보는 성공으로 세지 않습니다.

🔧 **기술 설명**
- 고정 시드 `20260813` 감사 도구에 상품 상세 URL 판별, 최종 URL 및 상품명+이미지 중복 제거, 통화별 저가 검증을 추가했습니다.
- 실제 렌더링 감사 결과는 `0.EngineTest/data/price_audit_150.json`에 저장되며 50 malls × 3 distinct products 조건을 충족합니다.
- Tier 2.5와 프로토타입 DOM fallback은 Product 구조화 데이터나 명시적인 상품 상세 신호가 없는 검색·카테고리 화면에서 가격을 가져오지 않습니다.

---

## 2026-08-13 — 가격 기준을 정가 + 기본 판매가로 통일

🟢 **쉬운 설명**
상품 페이지에는 정가, 기본 할인 가격, 쿠폰 예상가, 회원가, 옵션 추가금이 함께 보여
어느 가격을 저장해야 할지 모호했습니다. wishkit은 이제 **정가**와 **쿠폰·옵션 선택 전
기본 판매가**만 저장합니다. 쿠폰 예상가는 사용자마다 달라 제외하고, 옵션에 따라 최종
결제 금액이 달라질 수 있다는 안내를 공유 담기 화면에 표시합니다.

무신사 테스트 상품은 `32,000원`이 정가, `30,400원`이 기본 판매가입니다. 첫 화면의
`21,280원`은 30,400원에 30% 쿠폰을 적용한 값이며, 옵션 선택 후 장바구니에도
기본 판매가인 `30,400원`으로 담기는 것을 확인했습니다.

🔧 **기술 설명**
- Python 메타데이터 파서가 무신사의 `product:price:normal_price`를 정가로 인식한다.
- JSON-LD `priceType`과 회원 등급 조건에서 쿠폰·회원·멤버십·프로모션 가격을 제외한다.
- Tier 2.5 추출 결과를 `price`와 `originalPrice` 쌍으로 확장하고, 정가 유형과 조건부
  가격을 구분한다. DOM 폴백도 쿠폰·회원·카드·적립·배송 문맥을 제외한다.
- 구조화된 기본 판매가는 옵션 선택 전 대표값이므로 화면의 쿠폰 예상가로 덮어쓰지 않는다.
- 가격 쌍 정합성 및 무신사 메타 태그 회귀 테스트를 추가했다.

---

## 2026-08-12 — 쇼핑 앱 공유 목록 노출 및 공유 문장 인식 개선

🟢 **쉬운 설명**
쇼핑몰마다 상품을 공유하는 방식이 달라 wishkit이 공유 목록에 보였다가 안 보이거나,
목록에서 선택해도 `상품명 + 링크` 문장을 읽지 못하던 문제를 고쳤습니다. 이제 Android에서
텍스트뿐 아니라 상품 이미지가 첨부된 공유에도 wishkit이 표시되고, 공유 문장 어디에 있든
상품 링크를 찾아 공유 담기 화면으로 이동합니다.

🔧 **기술 설명**
- Android `MainActivity` intent filter에 `ACTION_SEND image/*`와
  `ACTION_SEND_MULTIPLE image/*`를 추가하고 중복된 `text/plain` 필터를 제거했다.
- `services/share_input.dart`를 추가해 공유 텍스트 내부의 첫 HTTP(S) URL을 검증하고,
  URL 뒤 문장부호를 제거한다. 서버의 상품명 힌트를 보존하기 위해 URL만 자르지 않고
  원본 `상품명 + URL` 문장을 공유 담기 화면에 전달한다.
- `main.dart`의 실행 중/콜드 스타트 공유 처리를 하나로 통합했다. 이미지 공유의 `message`와
  텍스트 공유의 `path`를 모두 확인하고, 같은 공유 이벤트의 중복 처리와 초기 intent 재실행을
  방지한다.
- `receive_sharing_intent 1.8.1`이 Android 이미지의 `EXTRA_STREAM`이 있으면 함께 전달된
  `EXTRA_TEXT`를 버리는 동작을 확인했다. `MainActivity.kt`에 전용 MethodChannel을 추가해
  이미지/다중 이미지 공유에 붙은 제목과 URL 문장을 앱 실행 중·종료 상태 모두 보존한다.
- `test/share_input_test.dart`에 순수 URL, 쿠팡형 여러 줄 문장, URL 뒤 문장부호,
  이미지 경로 + 메시지, 이미지 단독 공유 테스트를 추가했다.

> iOS 공유 목록 노출에는 별도의 Share Extension target과 App Group 설정이 필요하므로
> 이번 변경 범위는 현재 주 검증 플랫폼인 Android이다.

---

## 2026-08-10 — 대량 검증(의류몰 164개) + 가격 오탐 필터 추가

🟢 **쉬운 설명**
의류 쇼핑몰 164곳을 실제로 테스트해 **121곳에서 가격 자동 추출 성공**을 확인했습니다
(JSON-LD 89 · 화면 긁기 19 · OG 13). 그 과정에서 "배송비 3,000원" 같은 배너를
상품가로 잘못 집는 경우를 발견해, 배송/쿠폰 문맥의 숫자는 걸러내도록 고쳤습니다.

🔧 **기술 설명**
- `services/product_extract_js.dart`의 `domPrice`: 첫 매치만 쓰던 걸 순회 방식으로 바꿔
  1,000원 미만 및 배송/무료/쿠폰/적립/포인트/이상 문맥의 금액을 건너뛴다(오탐 방지).
- 검토했으나 도입 보류: 데이터레이어 `"price":NNNNN` 범용 추출 — 상품 페이지엔 추천/관련
  상품 가격이 여러 개라 엉뚱한 값을 고를 위험이 커서, 잘못된 자동가보다 Tier 3(사용자
  입력)이 안전하다고 판단(코드에 주석으로 근거 남김).
- 검증: 164개 배치 테스트(프로토타입 헤드리스 크롬 = Tier 2.5 동일 로직). 실패 43개는
  ①해외/일부 국내 봇 챌린지(→Tier 3), ②JS 데이터레이어 가격(→몰별 규칙 필요),
  ③죽은/재고소진 URL(엔진 문제 아님)로 분류. 상세는 세션 기록 참조.

---

## 2026-08-10 — 상품명 추출 정교화 (사이트 공용 og:title 대응)

🟢 **쉬운 설명**
무인양품처럼 모든 페이지의 공유 제목이 똑같은("MUJI 무인양품 공식 온라인스토어")
사이트에서, 상품명이 그 공용 제목으로 잡히던 걸 고쳤습니다. 이제 화면의 실제
상품명(예: "저지 크루넥 반소매 티셔츠")을 씁니다. 실기기에서 재검증 통과.

🔧 **기술 설명**
- `services/product_extract_js.dart`: og:title 이 화면 `<h1>` 과 전혀 겹치지 않으면
  사이트 공용 제목으로 보고 h1(`domName`)을 상품명으로 채택(`useDomName`). 데스크톱
  프로토타입의 로직을 온디바이스 추출 JS에 이식. `source.name` 도 `dom` 으로 표기.
- 재검증(실기기): 무인양품 name="저지 크루넥 반소매 티셔츠"(dom)·price=12900,
  무신사 name·price(json-ld) 그대로 — 3개 테스트 통과.

---

## 2026-08-10 — Tier 2.5 실기기 검증 + 통합 테스트 추가

🟢 **쉬운 설명**
재통합한 WebView Tier 2.5 가 실제 안드로이드 폰에서 잘 도는지 확인했습니다.
무신사(78,000원)·무인양품(12,900원) 상품 페이지에서 가격을 자동으로 뽑아내는 걸
실기기에서 검증했고, 이 검증을 언제든 다시 돌릴 수 있게 자동 테스트로 남겼습니다.
(무신사는 JSON-LD 경로, 무인양품은 화면 긁기 경로 — 두 방식 모두 실기기에서 동작 확인.)

🔧 **기술 설명**
- `integration_test/webview_scraper_test.dart` 신규: 로그인·엔진서버·UI 없이
  `WebViewScraper.extract()` 를 직접 호출해 가격 추출을 검증. 실행:
  `flutter test integration_test/webview_scraper_test.dart -d <device>`.
- `pubspec.yaml` dev_dependencies 에 `integration_test`(Flutter SDK) 추가.
- 검증 결과(실기기 Samsung, Android): `isSupported=true`, 무신사 json-ld=78000,
  무인양품 dom=12900 — 3개 테스트 전부 통과.
- 함께 확인: 재통합 브랜치의 `flutter build apk --debug` 성공(163MB) —
  Firebase(google-services) + flutter_inappwebview 가 한 빌드에서 충돌 없이 링크됨.
- (알려진 개선점: 무인양품은 og:title 이 사이트 공용이라 상품명이 "MUJI 무인양품
  공식 온라인스토어"로 잡힘 — 가격은 정확. 상품명 정교화는 추후.)

---

## 2026-08-10 — WebView Tier 2.5 를 최신 main(인증·Firebase·리브랜딩) 위로 재통합

🟢 **쉬운 설명**
그동안 팀이 로그인·이메일 인증(Firebase)·앱 리브랜딩(wishkit)·seed 제거를 크게
진행해서, 옛 스냅샷 기준으로 만든 WebView Tier 2.5 기능을 **최신 main 위에 다시
얹었습니다.** 기능 동작은 그대로이고, 팀의 Firebase 설정·리브랜딩과 충돌 없이
공존하도록 병합했습니다. 앱은 `flutter analyze` 통과 상태입니다.

🔧 **기술 설명**
- 최신 `origin/main`(21커밋 진행분: Firebase Auth/Firestore, `com.softstudio.wishlist`
  리브랜딩, seed 제거)에서 새 브랜치 `feat/webview-tier-2.5` 를 만들어 재적용.
- 기능 파일은 main 이 안 건드려 깨끗이 적용: `parsing_bridge.dart`,
  `share_intake_screen.dart`, 신규 `config.dart`·`product_extract_js.dart`·
  `webview_scraper.dart`.
- `models.dart` 의 `ParsedProductInfo` 에 `onDeviceExtracted`·`mergeOnDevice` 추가
  (main 은 `Product.fromJson`·`AppUser` 만 바꿔 충돌 없음).
- 빌드 병합: main 의 google-services 플러그인·리브랜딩을 유지한 채 AGP 8.10.1,
  Java/Kotlin 17, cleartext 허용, `flutter_inappwebview` 추가,
  `receive_sharing_intent` 1.8.1 고정을 그 위에 얹음.
- 이전 `fix/build-config` 브랜치는 이 브랜치로 대체됨(빌드 변경은 WebView 의존성과
  분리하면 의미가 없어, 기능과 한 브랜치로 합침).

---

## 2026-08-07 — README에 개발 환경/버전 정보 추가

🟢 **쉬운 설명**
팀원이 환경을 맞출 때 참고하도록, 이 프로젝트가 쓰는 Flutter·Dart·Python·안드로이드
빌드 툴의 버전을 README에 표로 정리했습니다. 초기본에서 바뀐 항목은 ★로 표시했습니다.

🔧 **기술 설명**
- `README.md`에 "개발 환경 / 버전 정보" 섹션 추가: Flutter 3.44.3 / Dart 3.12.2,
  주요 pub 패키지 resolved 버전, Python 3.14.6 + 엔진 requirements, Android
  툴체인(Gradle 8.12 / AGP 8.10.1 / Kotlin 2.1.0 / compileSdk 36 / minSdk 24 /
  JVM target 17). CHANGELOG 링크도 함께 명시.

---

## 2026-08-07 — 엔진 빠른 테스트 스크립트 추가

🟢 **쉬운 설명**
엔진이 잘 도는지 확인하려고 매번 무거운 에뮬레이터를 켤 필요 없이, **서버에 URL만
던져 결과를 표로 보는 스크립트**를 추가했습니다. 어떤 몰이 몇 번 티어로 처리되는지
(자동으로 가격이 나오는지, 사용자 입력이 필요한지)를 몇 초 만에 확인할 수 있습니다.

🔧 **기술 설명**
- `parsing-engine/server/scripts/try_engine.py` 신규. 서버 `POST /parse` 를 여러 URL로
  호출해 `resolved_tier`·가격·`missing_fields`·제목을 표로 출력. 인자로 URL을 주면
  그 URL들을, 없으면 기본 샘플(29CM·SSG·무신사·무인양품·올리브영)을 테스트.
  Windows 콘솔 한글 깨짐 방지로 stdout을 UTF-8로 재설정. 서버 엔진(Tier 1/2/3)만
  검증하며 앱 Tier 2.5(단말 WebView)는 포함하지 않음.
- 사용: `python scripts/try_engine.py [url ...]` (서버가 8000 포트에 떠 있어야 함)

---

## 2026-08-07 — 온디바이스 WebView Tier 2.5 병합 + Android 빌드 정상화

두 갈래의 작업입니다. **A**가 이번의 본 목적(엔진 전략 병합)이고,
**B**는 그걸 실제 안드로이드에서 돌리기 위해 필요했던 기존 환경 문제 수정입니다.

### A. 단말 WebView 보완 계층 추가 (Tier 2.5)

🟢 **쉬운 설명**
기존 파싱 엔진(서버)은 약관 준수를 위해 "공식 API → 표준 메타데이터"만 씁니다.
그래서 쿠팡·네이버·무신사·올리브영·자라·무인양품처럼 서버가 가격을 못 얻는 몰이 많고,
그런 상품은 사용자가 가격을 직접 입력해야 했습니다.

이번에 **앱(사용자 폰) 쪽에 안 보이는 브라우저(WebView)를 한 겹 추가**했습니다.
서버가 가격을 못 채운 상품만, 앱이 그 상품 페이지를 몰래 한 번 열어 가격·이름·사진을
자동으로 뽑아 채웁니다. 사용자 본인 폰·본인 세션으로 자기가 저장하려는 상품 1건을 여는
것이라, 서버가 대량으로 긁는 것과 달리 차단·약관 리스크가 훨씬 낮습니다.

- 서버가 이미 가격을 줬으면 → WebView는 **안 돕니다** (낭비 없음)
- WebView가 실패해도 → 원래 서버 결과로 그대로 저장 (**저장은 절대 안 깨짐**)
- WebView가 없는 환경(웹·윈도우)에서는 → 자동으로 건너뜀 (기존 동작 유지)
- **팀 Python 엔진은 한 줄도 안 바꿨습니다.**

수집 우선순위: `Tier1 공식 API → Tier2 서버 메타데이터 → [신규] Tier2.5 단말 WebView → Tier3 사용자 입력`

🔧 **기술 설명**

| 파일 | 상태 | 변경 |
|---|---|---|
| `flutter_app/lib/services/product_extract_js.dart` | 신규 | WebView 안에서 `evaluateJavascript`로 실행되는 추출 스크립트. JSON-LD(`Product` + **`ProductGroup`/`hasVariant`** — 서버 파서가 놓치는 자라·유니클로·나이키 커버), Open Graph, 범용 DOM(h1·"12,345원"/"₩12,345") 순으로 추출. 자라 원화 ÷100 버그 보정 포함. 결과는 JSON 문자열로 반환. |
| `flutter_app/lib/services/webview_scraper.dart` | 신규 | `HeadlessInAppWebView`로 페이지를 백그라운드 로드 → 가격이 보일 때까지 1초 간격 폴링(최대 12초) → 차단/빈 페이지면 몰 홈을 1회 거친 뒤 재시도(쿠팡 대응). `TargetPlatform.android/iOS`에서만 동작(`isSupported`). |
| `flutter_app/lib/services/parsing_bridge.dart` | 수정 | `_fillOnDevice()` 추가. 서버 응답의 `price<=0` 또는 `missing_fields`에 price가 있을 때만 `WebViewScraper.extract()` 호출 후 병합. `baseUrl` 기본값을 `AppConfig.engineBaseUrl`로 교체(B 참조). |
| `flutter_app/lib/models/models.dart` | 수정 | `ParsedProductInfo`에 `onDeviceExtracted` 필드와 `mergeOnDevice()` 추가. 서버가 채운 값은 유지하고 비어 있는 칸(가격·이름·사진)만 단말 추출값으로 채운 뒤 `missing_fields` 재계산. |
| `flutter_app/lib/screens/share/share_intake_screen.dart` | 수정 | 결과 카드 배지에 `onDeviceExtracted`면 "Tier 2.5 · 단말에서 추출" 표시. `_save()`에서 플래그 보존. |

의존성: `flutter_app/pubspec.yaml`에 `flutter_inappwebview: ^6.1.5` 추가.

### B. Android 빌드·실행 정상화 (기존 환경 문제)

🟢 **쉬운 설명**
안드로이드에서 앱을 처음 빌드하려니 여러 곳에서 막혔는데, **이번 기능 때문이 아니라
프로젝트의 안드로이드 설정이 최신 라이브러리와 안 맞아서** 생긴 문제였습니다(팀도 언젠가
겪었을 것). 순서대로 다 뚫었고, 덤으로 **원래 있던 버그(안드로이드에서 서버에 접속이
안 되던 문제)**까지 같이 고쳤습니다. 이제 `flutter run`으로 바로 실행됩니다.

🔧 **기술 설명**

| 파일 | 변경 | 이유 |
|---|---|---|
| `flutter_app/lib/config.dart` | 신규. 서버 주소를 플랫폼별로 결정: Android 에뮬레이터 → `http://10.0.2.2:8000`, 그 외 → `127.0.0.1:8000`, `--dart-define=ENGINE_BASE_URL=...`로 덮어쓰기 가능. | **기존 버그**: `parsing_bridge.dart`에 `127.0.0.1` 하드코딩 → 안드로이드에서 호스트 서버에 접속 불가였음. |
| `.../android/app/src/main/AndroidManifest.xml` | `<application>`에 `android:usesCleartextTraffic="true"` 추가. | Android 9+는 평문 HTTP를 기본 차단 → `http://10.0.2.2:8000` 서버 호출이 막혀서. |
| `flutter_app/pubspec.yaml` | `receive_sharing_intent`를 `^1.8.1` → **`1.8.1` 고정**. | 1.9.0이 아직 stable로 배포되지 않은 `compileSdk 37`을 요구해 빌드 불가. 1.8.1은 34 요구. |
| `.../android/settings.gradle.kts` | Android Gradle Plugin `8.7.3` → **`8.10.1`**. | 새로 들어온 `androidx.core:1.17.0`(WebView 의존성)이 AGP 8.9.1+ 요구. Gradle 8.12와 호환되는 최신 라인이 8.10. |
| `.../android/build.gradle.kts` (루트) | `subprojects`에 모든 플러그인 모듈의 Java·Kotlin JVM 타겟을 17로 통일하는 블록 추가(`plugins.withId("com.android.library")` + `KotlinCompile` `configureEach`). | AGP 8.10의 JVM-target 검증이, 구형 플러그인의 Java 1.8과 JBR 21의 Kotlin 타겟 불일치를 오류로 처리. |
| `.../android/app/build.gradle.kts` | `:app`의 Java·Kotlin 타겟 `11` → **`17`**. | 위와 같은 정합성(루트에서 `:app`은 이미 평가 완료라 못 바꿔 자체 파일에서 조정). |

### 검증

- `flutter analyze` — 신규/수정 코드 오류·경고 0 (기존 deprecation 2건만 잔존)
- `flutter build apk --debug` — **성공** (`build/app/outputs/flutter-apk/app-debug.apk`)
- ⚠️ Tier 2.5 기능은 **Android/iOS에서만** 동작 — 웹/윈도우 실행으로는 확인 불가.
  실행: 에뮬레이터(`Pixel_10`) → 엔진 서버 → `flutter run -d emulator-5554`
