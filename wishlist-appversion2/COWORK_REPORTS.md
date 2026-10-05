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
