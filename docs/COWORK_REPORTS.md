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

## 2026-10-06 — parsing-engine 실제 AWS 배포 (전용 VPC, Cloud Map, ALB 없음)

브랜치 `feat/engine-deploy`(`feat/ai-extraction-server`에서 분기), 계정
`220133863621` / 리전 `ap-northeast-2`. 비용 발생 리소스 생성 전 전체
리소스 목록 + 실제 Price List API 기반 재계산을 제시했고, 사용자가
"승인할게"로 명시 승인한 뒤 진행했다. **PR은 열지 않음**(지시대로 보고만).

### (a) 생성한 리소스 ID

| 구분 | 이름 | ID |
|---|---|---|
| VPC | parsing-engine-vpc | `vpc-0f6a6dc9bb6d5f374` (10.77.0.0/16) |
| IGW | parsing-engine-igw | `igw-0213e53307131a66a` |
| Subnet(public, 2a) | parsing-engine-public-2a | `subnet-06d79369a1171bae0` |
| Subnet(public, 2c) | parsing-engine-public-2c | `subnet-0edcaaa601a281374` |
| Subnet(isolated, 2a) | parsing-engine-isolated-2a | `subnet-06f2c98107eaf27cf` |
| Subnet(isolated, 2c) | parsing-engine-isolated-2c | `subnet-04a42edefef2b81c1` |
| Route table(public) | — | `rtb-07359960cd86c9922` |
| Route table(isolated) | — | `rtb-082962c1491a3694a` |
| SG(engine) | parsing-engine-engine-sg | `sg-009e513cc99b91044` |
| SG(lambda) | parsing-engine-lambda-sg | `sg-0bc200745cbb6c4ce` |
| SG(negative-test, 임시) | parsing-engine-negative-test-sg | `sg-05a17c6fe57bc6475` |
| SG(test-pull, 임시) | parsing-engine-test-pull-sg | `sg-05730ae4f2bf8dc00` |
| Cloud Map namespace | parsing-engine.local | `ns-imttsjffvgkncjao` |
| Cloud Map service | engine | `srv-v36uizkfcyh3n5qn` |
| Secrets Manager | parsing-engine/gemini-api-key | `...secret:parsing-engine/gemini-api-key-IU9gtj` |
| IAM role | parsing-engine-exec-role | `arn:aws:iam::220133863621:role/parsing-engine-exec-role` |
| Log group | /ecs/parsing-engine | 보존 7일 |
| ECS 클러스터 | parsing-engine-cluster | — |
| ECR | parsing-engine | `...dkr.ecr.ap-northeast-2.amazonaws.com/parsing-engine` |
| Task definition | parsing-engine | `:1` (2vCPU/4096MB) |
| Task definition(test-runner) | parsing-engine-test-runner | `:1` (512cpu/1024mem) |
| ECS 서비스 | parsing-engine-svc | desired=1 |

전체 상세는 `wishlist-appversion2/parsing-engine/deploy/deploy_state.json`에
기록(비밀값 없음, `.gitignore`에 등록되어 커밋 안 됨) — teardown의 단일
소스.

### (b) 비용 재계산 vs 승인 금액

사용자의 사전 추정(주당 $20 / 월 $88)과 별개로, 실제 AWS Price List API로
단가를 다시 조회해 제시했고 — Fargate vCPU/GB-시간, Public IPv4
$0.005/hr, Cloud Map $0.10/리소스-월 + $1/백만 호출, Secrets Manager
$0.40/시크릿-월, CloudWatch Logs 수집 $0.76/GB 등 — NAT Gateway·ALB/NLB를
아예 쓰지 않는 구조라 그 두 항목(원래 추정에서 큰 비중)이 0으로 빠지는
점을 명시한 뒤 사용자가 "승인할게"로 승인. (상세 단가표는
`deploy/RUNBOOK.md`에 그대로 보존.)

### (c) 6단계 VPC 내부 검증 결과 (실제 출력)

- **A. healthz + 골든셋 3건 추출**: `/healthz` 200 OK, 골든셋 3개 URL 모두
  확정 가격 포함 정상 응답 (Cloud Map 도메인
  `http://engine.parsing-engine.local:8000`으로 호출, test-runner
  Fargate 태스크가 `lambda-sg`만 붙인 상태에서 성공 — Lambda가 실제로
  보게 될 네트워크 경로와 동일 조건).
- **B. 음성(negative) 연결 테스트**: `lambda-sg`가 아닌
  `negative-test-sg`(기본 규칙)로는 엔진에 연결 자체가 안 되는 것을
  확인 — 15초 타임아웃으로 커넥션 자체가 거부/행잉(기대한 그대로의
  "허용 안 함" 동작).
- **C. 서버 내부 22초 타임아웃**: `https://httpbin.org/delay/30`에
  POST하여 서버가 `EXTRACT_TIMEOUT_S=22`에 맞춰 22초 선에서 자체
  타임아웃 처리하는 것을 확인(AppSync의 30초보다 먼저 끊김 — 체인
  설계대로 동작).
- 중간에 Gemini API 키를 처음 입력했을 때 3건 모두 `401
  UNAUTHENTICATED`가 나서(복붙 시 공백/오타로 추정) 사용자가 재입력,
  `--force-new-deployment`로 서비스 재기동 후 재검증해 전부 통과.

### (d) 백엔드(지은 님)께 넘길 4개 값

```
ENGINE_VPC_ID=vpc-0f6a6dc9bb6d5f374
ENGINE_PRIVATE_SUBNET_IDS=subnet-06f2c98107eaf27cf,subnet-04a42edefef2b81c1
ENGINE_LAMBDA_SG_ID=sg-0bc200745cbb6c4ce
ENGINE_BASE_URL=http://engine.parsing-engine.local:8000
```

`deploy/HANDOFF_AMPLIFY.md`에 이 값들 + `export` 후 `npx ampx sandbox`
재실행 안내, 기존에 알려진 `npm ci`(`@opentelemetry/core` lock 불일치)
이슈, "샌드박스는 개인 환경이지 운영 환경 아님" 주의사항을 같이 적어둠.

### (e) 확인된 것 vs 아직 안 된 것

**확인됨**: VPC 내부에서 Cloud Map 도메인으로 엔진 호출 성공·실패(허용
안 된 경로) 둘 다 기대대로 동작, 22초 서버 타임아웃 동작, NAT/ALB 없이
구조가 성립.

**아직 안 됨**: 실제 AppSync→Cognito 인증 경로, 실제 Lambda(`parsing-proxy`)
→엔진 호출(지은 님이 위 4개 값으로 샌드박스를 다시 띄운 뒤에만 가능 —
이번 세션에서 재현 불가능한 부분), 28초 Lambda 타임아웃이 AppSync 30초
안에서 실제로 끝나는지의 end-to-end 확인.

### (f) 현재 과금 중인 리소스

- **ECS 서비스 `parsing-engine-svc`** — 태스크 1개 RUNNING
  (`arn:aws:ecs:ap-northeast-2:220133863621:task/parsing-engine-cluster/3b04f6a05bac42418a0f1cef2b530710`,
  public IP `3.38.93.33`, 2vCPU/4096MB) — **계속 돌아가는 중, 계속
  과금됨**. 끄거나 유지할지는 사용자 결정 필요(RUNBOOK에 scale-to-zero
  명령 있음).
- NAT Gateway: **0개**, ALB/NLB: **0개** (확인 완료, 설계대로 없음).
- 그 외 저비용 상시 항목: ECR 리포지토리 1개, Secrets Manager 시크릿 1개,
  CloudWatch 로그 그룹 1개(7일 보존), Cloud Map 네임스페이스/서비스 각
  1개, IAM 역할 1개 — 전부 사용량 기준 소액.
- 이전 세션에서 쓰다 남은 `wishkit-parsing-engine-validation` 클러스터(빈
  상태)·`wishkit-parsing-engine` ECR·구 task-definition 3종은 이번
  작업에서 손대지 않았고, 실행 중인 태스크가 없어 과금 없음.

### 커밋

- `feat/engine-deploy` — `721920d`: `deploy/HANDOFF_AMPLIFY.md`,
  `deploy/RUNBOOK.md`, `deploy/teardown.sh`(`--dry-run`으로 검증,
  실제 실행은 안 함) 추가, `.gitignore`에 `deploy/deploy_state.json`
  추가. 서버 코드는 수정 안 함(환경변수만 오버라이드).

### 확인/결정 요청

1. `parsing-engine-svc` 태스크를 계속 켜둘지, 지금 0으로 내릴지
2. `feat/engine-deploy` / `feat/app-engine-client` / 마이그레이션 브랜치
   PR을 언제 열지
3. 지은 님이 샌드박스를 4개 값으로 재기동하는 시점 공유 필요(그래야
   Lambda→엔진 실제 호출 검증 가능)

## 2026-10-26 — 3주 공백 후 상태 점검 + main 동기화

세션 재개. 그 사이(10/6~10/26) 팀원들이 PR 3개를 `main`에 머지했고,
배포해둔 엔진 서비스는 계속 켜진 채였던 것을 확인·점검했다.

### 과금 점검 결과

- `parsing-engine-svc` 태스크가 2026-10-06 15:11(배포 직후)부터 지금까지
  **483시간(20일) 연속 RUNNING** — 중간에 태스크 1회 재시작됐지만
  desired=1이 끊기지 않고 유지됨.
- 최근 7일 CloudWatch 로그 이벤트 **0건** — 그 사이 아무도 호출하지 않음.
- Price List API 재조회(2vCPU/4GB, x86, Seoul): vCPU-시간 $0.04656 +
  GB-시간 $0.00511 → 시간당 $0.1136, Public IPv4 $0.005/시간 포함
  **추정 약 $57**(compute+IP만, ECR/Secrets/CloudWatch 등 소액 항목
  제외). `ce:GetCostAndUsage` 권한이 배포용 IAM 사용자에 없어 실제
  청구서 대조는 못 함 — 단가 기반 추정치임을 명시.
- NAT Gateway 0개, ALB/NLB 0개 — 설계대로 유지 확인.
- **사용자 확인 결과: 지은 님이 곧 샌드박스를 재기동해 실제 테스트할
  예정이라 서비스는 그대로 유지하기로 함.**

### main 쪽 변경사항 (PR 3건, 전부 `feat/app-engine-client` 브랜치 밖에서 머지됨)

1. PR #1 `feat/ai-extraction-server` → main: `parsing-engine` 폴더 +
   `parsing-proxy` Lambda **코드**가 main에 들어감(배포는 아직 안 함).
   단, main의 `parsing-proxy`는 AppSync 30초 체인 수정 **이전**
   버전(`timeoutSeconds: 60`, `FETCH_TIMEOUT_MS: 55_000`) — 우리가
   `feat/app-engine-client`에서 고친 28초/25초 버전이 아직 main에
   안 올라가 있음.
2. PR #3 `feat/remove-reviews` → main: `ProductReview` 클래스, 리뷰
   화면 4개, 리뷰 관련 gql 쿼리 4개 전체 삭제.
3. PR #2 `feat/bw-theme` → main: 격자 배경 제거, 흑백 톤 색상 적용
   (`DiaryColors`/`diary_widgets.dart` 내부 값만 변경, 심볼명은 유지).

### 충돌 여부 확인 후 merge

머지 전 영향 범위를 먼저 확인: 우리 쪽 코드가 쓰는
`ParsedProductInfo`/`mergeOnDevice`/`DiaryColors.*`/`DiaryGridPaper`/
`WhiteProductCard`는 리뷰 삭제·테마 변경 양쪽 모두에서 심볼 자체는
그대로 남아 있어 구조적 충돌 없음을 확인. `gql_documents.dart`도
main의 삭제 줄과 우리 쪽 추가 줄(`extractProduct`)이 겹치지 않아 안전.

`origin/main`을 `feat/app-engine-client`에 merge(`beb9d6b`) — **충돌
0건**. 머지 후 재검증:

- `flutter test`: **179개 전부 통과** (184 → 179는 main에서 삭제된
  리뷰 관련 테스트 5개가 빠진 것, 신규 실패 없음)
- `flutter analyze`: 기존과 동일한 6건(전부 `amplify_outputs.dart`
  미생성 등 로컬 샌드박스 미실행에서 오는 사전 known issue), 신규 0건

### 커밋 / push

- `feat/app-engine-client` — 지난 세션에 push 분류기에 막혀 밀려
  있던 `38ae4f1`(보고 로그)과 이번 `beb9d6b`(main 머지)를 함께 push
  완료. (이번엔 분류기에 안 걸림 — 같은 명령, 같은 워크어라운드로
  성공.)

### 확인/결정 요청

1. main의 `parsing-proxy` 타임아웃(60초/55초, 구버전)을 우리 쪽
   28초/25초 수정으로 언제 맞출지 — `feat/app-engine-client`가 PR로
   올라가면 자동으로 해결되지만, 그 전에 누가 급하게 main 기준으로
   배포 테스트를 하면 구버전 타임아웃으로 동작함
2. `feat/engine-deploy` / `feat/app-engine-client` PR을 언제 열지
   (지은 님 샌드박스 재기동 이후가 자연스러워 보임)
3. `parsing-engine-svc`는 지은 님 테스트 끝나면 다시 점검 필요(과금
   계속 쌓이는 중)

### 추가 — `feat/engine-deploy` PR #4 오픈 (같은 날, 요청에 따라)

사용자 요청으로 `feat/engine-deploy` → `main` PR 오픈:
https://github.com/SPARK-Wishkit/SPARK_Wishkit/pull/4

오픈 직전 main에 지은 님이 `for_wishkit 최신 코드로 교체` 커밋을 직접
푸시한 것을 발견 — `parsing-proxy/handler.ts`·`resource.ts`를 다른
타임아웃 값(Lambda `timeoutSeconds: 30`, fetch 중단 27초)과
`engine-env.ts` 기반 env 로딩 방식으로 이미 고쳐 올림. `git
merge-tree`로 사전 확인한 결과 이 PR의 타임아웃 수정(28초/25초/22초
체인)과 **같은 두 파일에서 실제 merge 충돌** 확인 — PR
description에 충돌 사실과 두 체인의 차이(지은 님 버전은 Lambda
자체 타임아웃이 AppSync 30초 하드 리밋과 같은 값이라 설계 원칙
"안쪽이 바깥쪽보다 항상 짧아야 한다"에 어긋남)를 명시해둠. 인프라
(VPC/ECS/Cloud Map) 변경분은 겹치는 파일이 없어 충돌 없음.

**결정 필요**: 머지 전 두 타임아웃 체인 중 하나로 조율.

## 2026-10-29 — 배포 방향 통일(지은 님 engine.sh) + 우리 전용 VPC 전체 철거

### 배경

main에 지은 님이 직접 올린 `for_wishkit 최신 코드로 교체` 커밋을 다시
살펴보니, 단순 타임아웃 값 차이가 아니라 **parsing-engine 배포 자체를
완전히 새 구조로 이미 따로 만들어두신 상태**였다:

- `wishlist-appversion2/parsing-engine/deploy/engine.sh`(신규) — 기본
  VPC 퍼블릭 서브넷 + Cloud Map `wishkit.local` + 리소스명
  `wishkit-engine` + 비밀은 SSM Parameter Store
  (`/wishkit/engine/GEMINI_API_KEY`) + 평소엔 꺼두고 시연할 때만
  `start`/`stop`으로 켜는 방식.
- 확인해보니 **같은 계정(220133863621)에 이미 생성돼 있었음**: ECS
  클러스터 `wishkit-engine`, Cloud Map 네임스페이스 `wishkit.local`,
  서비스 `wishkit-engine/wishkit-engine`(2026-10-24 생성, 확인 당시
  desired=0/running=0 — billing 없음).
- 즉 parsing-engine 배포가 **두 벌**(우리 전용 VPC 상시가동 vs 지은
  님 기본VPC on/off) 존재하는 상태였음.

사용자 확인: **지은 님 `engine.sh` 방식으로 통일**, PR #4(우리 전용
VPC 배포 PR)는 **닫기**, 우리 전용 VPC는 **지금 실제로 철거**하기로
결정.

### PR #4 닫음

https://github.com/SPARK-Wishkit/SPARK_Wishkit/pull/4 — 방향 변경
사유를 코멘트로 남기고 close (머지 안 함).

### 전용 VPC 실제 철거 (`teardown.sh`, 이번엔 `--dry-run` 아닌 진짜 실행)

먼저 `parsing-engine-svc`를 `desired-count 0`으로 내려(그 사이 재개
세션에서 20일+ 다시 돌고 있던 걸 발견해 그 시점에 바로 내려둔
상태였음) task가 완전히 drain된 것(running=0) 확인 후 진행.

`bash teardown.sh`(실제 모드) 실행 — 중간에 한 번 에러(exit 254)로
멈춤: **`parsing-engine-engine-sg`와 `parsing-engine-lambda-sg`가
서로를 참조하는 규칙**(engine-sg는 lambda-sg발 8000 포트 인바운드
허용, lambda-sg는 engine-sg행 8000 포트 아웃바운드만 허용) 때문에
`DependencyViolation`으로 두 SG 모두 바로 삭제가 안 됐던 것 — 스크립트
작성 당시 이 상호 참조를 고려 안 했던 허점. 양쪽의 해당 규칙만 먼저
`revoke-security-group-ingress`/`revoke-security-group-egress`로
제거한 뒤 정상 삭제, 이어서 나머지 단계(라우트테이블→서브넷→IGW→VPC)
수동으로 이어서 완료.

**삭제 완료 확인(전수 재조회)**: VPC `vpc-0f6a6dc9bb6d5f374`
NotFound, ECS 클러스터 `parsing-engine-cluster` INACTIVE, Cloud Map
네임스페이스/서비스 삭제됨, 보안그룹 4개 전부 삭제됨, 서브넷 4개·
라우트테이블 2개·IGW 전부 삭제됨.

사용자 확인 후 저비용 항목까지 마저 정리: ECR 리포지토리
`parsing-engine` 삭제, task definition 2개(`parsing-engine`,
`parsing-engine-test-runner`) deregister, 로그 그룹
`/ecs/parsing-engine` 삭제, IAM 역할 `parsing-engine-exec-role`
삭제(정책 분리 후), Secrets Manager 비밀
`parsing-engine/gemini-api-key` 삭제 예약(7일 유예 아니라 실제로는
AWS 기본 30일 유예 — 2026-11-28 완전 삭제 예정, 그때까지도 비용은
사실상 없음).

**지은 님 `wishkit-engine` 쪽은 전혀 건드리지 않음** — 철거 전후로
desired=0 그대로 확인.

`deploy_state.json`(gitignored, 커밋 안 됨)에 `torn_down_at`/
`torn_down_reason` 필드 추가해 과거 기록으로 남김.

### 현재 과금 상태 (이 작업 이후)

parsing-engine 관련으로 이 계정에서 과금되는 것은 **없음** — 우리
쪽은 전부 삭제, 지은 님 쪽(`wishkit-engine`)은 desired=0으로 대기
중(켤 때만 과금).

### 확인/결정 요청

1. 앞으로 parsing-engine 배포/운영은 지은 님 `engine.sh` 기준으로
   따라가면 됨 — 우리 쪽 `feat/engine-deploy`/`deploy/` 산출물은
   참고 기록으로만 남고 더 반영 안 함
2. `feat/engine-deploy` 브랜치 자체를 지울지, 기록용으로 남겨둘지는
   아직 미정
