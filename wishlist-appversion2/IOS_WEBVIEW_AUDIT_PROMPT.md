# iOS WebView 재확인 — 다른 작업자용 시작 프롬프트

64곳 전체를 다시 돌리지 마세요. 목적은 **blank 리셋 이후 이전 몰 페이지가 섞이는지**, 그리고 Android와 갈렸던 **SSG·반스·마리떼·Aritzia**만 확인하는 것입니다.

실기기 아이폰이 있으면 그걸 우선하고, 없으면 시뮬레이터로 해도 됩니다.

아래 블록을 새 Cursor 대화에 그대로 붙여 넣으면 됩니다.

---

```
wishkit iOS WebView 재확인을 진행해. 전체 64개 감사가 아니다. blank 리셋 이후 오염이 줄었는지, SSG/반스/마리떼/Aritzia가 어떻게 나오는지만 보면 된다.

## 저장소
- GitHub: soft-studio-team/2026-softstudio-project
- 브랜치: feat/webview-scraper-stabilize
- 최신을 pull 한다. 프롬프트 파일: wishlist-appversion2/IOS_WEBVIEW_AUDIT_PROMPT.md
- Draft PR: https://github.com/soft-studio-team/2026-softstudio-project/pull/28
- 앱 경로: wishlist-appversion2/flutter_app
- 패키지/표시 이름: com.softstudio.wishlist / wishkit
- 감사 러너: integration_test/webview_all_malls_audit_test.dart
- 인수인계: wishlist-appversion2/ENGINE_DEVELOPMENT_HANDOFF.md 섹션 0.4, 0.5
- 한국어로 답하고, 끝나면 커밋·푸시·PR #28 갱신. 절대 머지하지 말 것.
- PR #31(이전 iOS 시뮬레이터 64 문서)을 덮어쓰지 말 것.

## 금지
- git reset --hard, git checkout --, git clean 사용 금지
- 로그인, 결제, 사용자 데이터 삭제, 장바구니 삭제 금지
- 실기기/시뮬레이터 앱을 uninstall 하지 말 것. flutter test 기본값은 종료 시 앱을 지운다. 반드시 --no-uninstall
- 관리 쇼핑몰 전용 가격 규칙이 실패하면 JSON-LD/OG/DOM 범용 가격으로 우회하지 말 것. 가격은 null
- 고정 대기 시간만 늘리지 말 것
- 파이썬 서버를 켜거나 /parse 를 호출하지 말 것. 공유 담기는 WebView 전용이다

## 시작 절차
1. git fetch origin feat/webview-scraper-stabilize
   git checkout feat/webview-scraper-stabilize
   git pull --ff-only origin feat/webview-scraper-stabilize
2. 작업 루트를 저장소 루트로 옮긴다.
3. flutter devices 로 iPhone 실기기 또는 시뮬레이터 ID를 확인한다. iOS 기기가 없으면 중단하고 보고한다. 실기기가 있으면 시뮬레이터보다 실기기를 쓴다.
4. cd wishlist-appversion2/flutter_app
5. 단위 테스트:
   flutter test test/product_extract_js_sync_test.dart test/webview_scraper_result_test.dart test/parsing_bridge_test.dart test/share_input_test.dart
6. WEBVIEW_JS_PROBE 가 2 또는 2.0 이 아니면 몰 결과를 가격 통과로 보지 말 것.

## 감사 명령 (DEVICE_ID를 실제 기기 ID로)
반드시 --no-uninstall. 한 번에 64개를 돌리지 말 것.

1) 오염 확인 — 이전 몰 DOM이 다음 결과에 섞이면 실패다. finalUrl·상품명이 요청한 몰과 같아야 한다.
퀸잇 다음 브랜디:
flutter test integration_test/webview_all_malls_audit_test.dart -d DEVICE_ID --no-uninstall --dart-define=WEBVIEW_AUDIT_ONLY=56,57

탑텐 다음 무인양품:
flutter test integration_test/webview_all_malls_audit_test.dart -d DEVICE_ID --no-uninstall --dart-define=WEBVIEW_AUDIT_ONLY=10,11

코드그라피 다음 후아유:
flutter test integration_test/webview_all_malls_audit_test.dart -d DEVICE_ID --no-uninstall --dart-define=WEBVIEW_AUDIT_ONLY=33,34

2) Android와 갈렸던 몰:
flutter test integration_test/webview_all_malls_audit_test.dart -d DEVICE_ID --no-uninstall --dart-define=WEBVIEW_AUDIT_ONLY=24,31,37,40

인덱스: 24 SSG, 31 반스, 37 Aritzia, 40 마리떼.

시작 로그 WEBVIEW_JS_PROBE 와 각 줄 WEBVIEW_AUDIT_RESULT JSON을 저장한다.

## 비교용 (iOS 통과로 베끼지 말 것)
이전 iOS 시뮬레이터 64(PR #31): 퀸잇 DOM이 브랜디 등으로 새어 나왔고, 단독 재실행으로 덮어썼다. 이번 코드는 추출마다 about:blank onLoadStop을 기다린다. 오염이 다시 나오면 몰 이름·요청 URL·finalUrl을 적고, 범용 가격 우회로 고치지 말 것.

Android 실기기 최신:
- SSG PASS, 반스 PASS(올드스쿨 57000), Aritzia PASS, 마리떼는 전용 규칙 실패로 가격 null(PARTIAL_NO_PRICE)
- 현대Hmall·나이키·이랜드몰은 Android에서 PASS. 리바이스는 loading_timeout. iOS에서 리바이스 대기를 늘리지 말 것.
- SSG가 iOS에서 「접속이 잠시 제한되었습니다」이면 BLOCKED 가 맞다. 우회하지 말 것.
- 마리떼 iOS에서 전용 규칙으로 가격이 나오면 PASS로 적어도 된다. 안 나오면 가격 null을 유지한다.

PASS로 보고하려면 이름·이미지·양수 가격이 있어야 한다. 관리 몰은 source.price 가 site-adapter 여야 한다.

## 선택: 공유 담기
시간이 되면 반스 URL을 공유 담기에 넣어 이름·가격이 채워지는지, 가격이 없는 몰은 이름/사진/URL이 남고 가격만 직접 입력하면 저장되는지 본다. 파이썬 서버는 켜지 말 것.

## 검사 후 일반 앱 복구
flutter test 는 검사 전용 엔트리를 설치한다. 끝나면 일반 앱을 덮어씌운다. uninstall 하지 말 것.
flutter build ios --debug --no-codesign 이 실패하면 코드사인된 debug 설치를 쓴다.
flutter install -d DEVICE_ID
또는 Xcode에서 Runner를 일반 Debug로 설치. 사용자 데이터 삭제 금지.

## 보고
CHANGELOG와 ENGINE_DEVELOPMENT_HANDOFF.md에 iOS 재확인 결과를 남긴다. 오염 여부, SSG/반스/마리떼/Aritzia 분류, Android와 다른 점을 몰 이름·failureReason·finalUrl로 적는다.
커밋·푸시 후 PR #28을 draft로 갱신하고 머지하지 말 것.
```

---

## 한 줄 복붙용 브랜치

```bash
git fetch origin feat/webview-scraper-stabilize
git checkout feat/webview-scraper-stabilize
git pull --ff-only origin feat/webview-scraper-stabilize
```
