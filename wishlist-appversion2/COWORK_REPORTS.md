# Cowork 보고 로그

Claude Code 세션이 작업을 마칠 때마다 보고를 여기에 이어서 추가한다(날짜순, 가장 최근
항목이 맨 아래). 세션마다 새 파일을 만들지 않고 이 파일 하나에 계속 쌓는다.

---

## 2026-10-05 — 앱↔엔진 연동 코드 완료 (기본 꺼짐, 동작 변화 없음)

브랜치: `feat/app-engine-client` (`feat/ai-extraction-server` 위에 쌓음, PR #1 미머지
상태라 그 위에 올림), 커밋 `3007c31`, push 완료. **PR은 안 엶** — 지침대로 보고 후 지시
대기.

### 변경 파일 (6개)

| 파일 | 설명 |
|---|---|
| `lib/services/aws/engine_store.dart` (신규) | 기능 플래그 `kEngineEnabled`(기본 꺼짐), `ExtractedProductDto`, `EngineClient` 인터페이스, `AppSyncEngineClient` 구현 |
| `lib/services/aws/gql_documents.dart` | `extractProduct` 쿼리 1개만 추가 |
| `lib/services/parsing_bridge.dart` | `engine` 주입 + 엔진→WebView 폴백 로직 + `engineResultToOnDeviceExtract` 변환 함수 + 상단 주석 갱신 |
| `lib/screens/share/share_intake_screen.dart` | `ParsingBridge` 생성 1줄만 수정(TEAM_CONTRACT 약속4 표에 없는 파일이라 직접 고침) |
| `test/aws/engine_store_test.dart` (신규) | DTO 파싱·변환 함수·`AppSyncEngineClient` 단위 테스트 13개 |
| `test/parsing_bridge_test.dart` | 엔진 연동 통합 테스트 9개 추가 |

### 중요 발견 — `onDeviceExtracted` 오염 방지

`resolvedTier`/`engineUsed`/`priceConfidence`는 UI에서 전혀 안 읽히지만,
`onDeviceExtracted`는 실제로 "휴대폰에서 읽음" 배지에 쓰인다. 엔진 결과에 이 값을
`true`로 두면 서버 결과를 휴대폰에서 읽은 것처럼 잘못 표시할 뻔해서, `engineUsed`일
때는 명시적으로 `false` 처리했다.

### 검증 결과

- `flutter pub get` 성공
- `flutter analyze`: 기존 6건 그대로, 신규 0건(전부 안 건드린 파일)
- `flutter test`: 178개 전부 통과(기존 165 + 신규 13, 기존 테스트 전부 무변화)

### 공유 파일 수정 필요 — 없음

약속4 표(`main.dart`/`app_store.dart`/`pubspec.yaml`) 전부 안 건드림.

### 팀 공지 필요

`gql_documents.dart`에 `extractProduct` 쿼리 1개 추가함(파일 소유자는 백엔드 담당).
TEAM_CONTRACT 약속4 표에 추가할 문구 초안(직접 반영 안 함):

> `| lib/services/aws/gql_documents.dart | 엔진 담당이 extractProduct 1개만 추가 — 그 외는 백엔드 담당 소유, 고치기 전 공지 |`

### 확인됨 / 안 됨

**확인됨**: 가짜 `EngineClient`/`GqlRunner`로 성공·ambiguous·예외·타임아웃·USD·플래그꺼짐
전 분기 커버, 기존 동작 무변화.

**안 됨**: 실제 엔진 호출(배포 전), 실제 Cognito 토큰 경로(`AmplifyGqlRunner` 쪽이라
미검증), `ENGINE_ENABLED=true`로 실제 켰을 때 빌드/런타임 동작.

### 확인/결정 요청

1. 이 코드 검토 후 진행 방향 지시(PR 오픈 여부 등)
2. TEAM_CONTRACT 약속4 문구 추가 여부
3. `gql_documents.dart` 변경사항 백엔드 담당에게 공지

---

## 2026-10-05 — parsing-proxy 타입체크 시도 (소급 기록)

이 CLI 환경(Node 설치 직후)에서는 `npm ci`가 다음 오류로 막혀 타입체크를 실행하지
못했다:

```
npm error Missing: @opentelemetry/core@2.0.0 from lock file
```

대신 외부 의존성 없는 `logic.ts`를 Node 네이티브 TS 실행으로 직접 테스트해 8개
케이스 전부 PASS 확인(저장소 밖 임시 스크립트, 커밋 안 함).

이후 **Cowork가 클라우드 임시 사본에서 lock 파일을 재생성**(패키지 +8)해서
`tsc --noEmit -p amplify` 오류 0건을 확인했다 — 당시 의심 지점 4개
(`AppSyncResolverHandler` 타입 임포트, `iam.Role` 캐스팅, `vpcConfig` 대입,
`a.handler.function` 연결) 전부 타입 수준 통과. 원인은 npm 버전 차이가 아니라
**`package-lock.json` 자체의 불일치**였다 — 중첩된 `@opentelemetry/resources`·
`@opentelemetry/sdk-trace-base`가 `@opentelemetry/core@2.0.0`을 정확히 요구하는데,
lock에는 2.8.0/2.11.0만 기록돼 있었다. lock 재생성(의존성 +8건)을 실제로 커밋할지는
백엔드 담당과 상의가 필요해서 보류 중.

---

## 2026-10-05 — AppSync 30초 하드 리밋 대응 + 엔진 결과 WebView 보충

브랜치 2개 모두 작업, PR 미오픈.

### 배경

AppSync는 요청당 30초 고정 한도(조정 불가)라서, 기존 값(엔진 45초 / Lambda fetch
55초 / Lambda 60초 / 앱 50초)은 전부 30초에 먼저 잘려 의미가 없었다. 안쪽이
바깥쪽보다 항상 짧도록 체인을 다시 잡음: 엔진 `EXTRACT_TIMEOUT_S` 22초(배포 시
env로 지정, 코드 기본값 45는 안 건드림) < Lambda fetch 중단 25초 < Lambda
`timeoutSeconds` 28초 < AppSync 30초(고정). 앱 엔진 대기는 27초.

### 커밋

- `feat/ai-extraction-server` — `f0c5ca2`: `parsing-proxy/resource.ts`
  `timeoutSeconds` 60→28, `handler.ts` `FETCH_TIMEOUT_MS` 55_000→25_000, 관련
  주석 전부 새 체인 설명으로 교체. `backend.ts`에 남아있던 `60` 두 곳은 Cognito
  토큰 유효기간(분 단위)이라 이 체인과 무관 — grep으로 확인만 하고 안 건드림.
- `feat/app-engine-client` — `feat/ai-extraction-server`를 merge(충돌 없음)한 뒤
  `339b19a`:
  - `engine_store.dart`: `AppSyncEngineClient` 기본 timeout 50초→27초
  - `parsing_bridge.dart`: `_supplementFromWebView` 추가 — 엔진이 확정 가격을
    줬는데 이름/이미지가 비어 있으면 WebView를 최대 8초만 돌려 **빈 칸만** 채운다.
    가격·원가·신뢰도는 절대 안 건드림(WebView가 다른 값을 줘도 무시), WebView가
    실패·타임아웃이어도 엔진 결과를 그대로 씀(예외 안 샘)

### `mergeOnDevice` 재사용 검토 결과 — 재사용 안 함

`models.dart`의 `ParsedProductInfo.mergeOnDevice()`(약 843행)가 "빈 이름/이미지만
채운다"는 로직을 이미 갖고 있어 재사용을 검토했으나, **`onDeviceExtracted`를
무조건 `true`로 고정**하고 있어서 그대로 쓰면 엔진 가격 결과에도 "휴대폰에서
읽음" 배지가 잘못 붙는다. `models.dart`는 공유 파일이라 수정하지 않고, 대신
`parsing_bridge.dart`에 같은 "빈 칸만 채우기" 로직을 작게 새로 작성해
`onDeviceExtracted: false`를 명시적으로 유지했다. (제안: `mergeOnDevice`에
`onDeviceExtracted` 선택 인자를 추가하면 이 중복을 없앨 수 있음 — 백엔드/앱
담당 판단 필요, 직접 수정 안 함.)

### 검증 결과

- `flutter analyze`: 기존 6건 그대로, 신규 0건
- `flutter test` 전체: **184개 전부 통과**
- 파일별 실측(`flutter test <파일>` 개별 실행):
  - `test/aws/engine_store_test.dart`: **13개** (기존 12 + 이번에 추가한 timeout
    기본값 확인 1개)
  - `test/parsing_bridge_test.dart`: **17개** (기존 4 + 지난 세션 추가 8 + 이번
    보충 로직 5)

### ⚠️ 지난 보고("13+9, 178")의 오기 정정

전수 재확인 결과, 지난 항목(앱↔엔진 연동 코드 완료)의 테스트 개수 집계가 틀렸다.
숫자를 맞추려고 보정하지 않고 실제 재실행한 그대로 적는다:

- 당시 실제로는 `engine_store_test.dart` **12개**(13 아님), `parsing_bridge_test.dart`
  **신규 8개**(9 아님, 기존 4 포함 총 12개)였다 — 전체 합계 `178`(기존 158 + 신규
  12+8=20)은 그때 `flutter test` 실행 결과를 그대로 옮겨 적어서 맞았지만, 본문의
  "13개"/"9개"/"기존 165" 서술은 세는 과정에서 생긴 단순 집계 실수였다.
- 원인: 파일별로 따로 실행해서 정확히 세지 않고, 추가한 테스트 이름을 암산으로
  합산하다 잘못 셈. 이번 세션부터는 각 파일을 `flutter test <파일>`로 따로
  실행해서 출력 그대로 옮겨 적는 방식으로 바꿈(위 "파일별 실측" 참고).

### 확인/결정 요청

1. 위 두 커밋(`f0c5ca2`, `339b19a`) 검토
2. `mergeOnDevice`에 `onDeviceExtracted` 선택 인자 추가 제안 — 반영 여부
3. lock 파일 재생성(Cowork가 클라우드에서 검증한 것) 커밋 여부 — 백엔드 담당과 상의

### 안 된 것

실서버 호출, 실제 AppSync 30초 하드 리밋 동작(배포 후에만 확인 가능 — 지금은
숫자 체인이 이론상 30초 안에 들어오게만 맞춰둔 상태).
