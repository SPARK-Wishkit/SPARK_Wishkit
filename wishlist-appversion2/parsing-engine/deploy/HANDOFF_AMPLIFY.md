# 엔진 배포 완료 — Amplify 쪽에 필요한 값 (2026-10-06)

parsing-engine(AI 추출 서버)을 AWS Fargate에 올렸습니다. Lambda(`parsing-proxy`)가
VPC 안에서 이 엔진을 호출하도록 연결하려면, 아래 4개 값을 `amplify/backend.ts`가
읽는 환경변수로 넣고 **본인 샌드박스를 다시 띄워야** 합니다(`backend.ts`의 엔진 연동
블록이 이 4개 값이 없으면 일부러 배포를 막아두게 돼 있습니다).

## 필요한 값

| 환경변수 | 값 |
|---|---|
| `ENGINE_VPC_ID` | `vpc-0f6a6dc9bb6d5f374` |
| `ENGINE_PRIVATE_SUBNET_IDS` | `subnet-06f2c98107eaf27cf,subnet-04a42edefef2b81c1` |
| `ENGINE_LAMBDA_SG_ID` | `sg-0bc200745cbb6c4ce` |
| `ENGINE_BASE_URL` | `http://engine.parsing-engine.local:8000` |

## 적용 방법

```bash
export ENGINE_VPC_ID=vpc-0f6a6dc9bb6d5f374
export ENGINE_PRIVATE_SUBNET_IDS=subnet-06f2c98107eaf27cf,subnet-04a42edefef2b81c1
export ENGINE_LAMBDA_SG_ID=sg-0bc200745cbb6c4ce
export ENGINE_BASE_URL=http://engine.parsing-engine.local:8000

cd wishlist-appversion2/flutter_app
npx ampx sandbox
```

같은 터미널 세션 안에서 돌려야 환경변수가 유지됩니다. 매번 새로 export하기 귀찮으면
`.env.local` 같은 본인만의 파일(커밋 금지)에 넣고 `source` 해서 써도 됩니다.

## 왜 이 값들이어야 하는지

- `parsing-proxy` Lambda를 엔진과 **같은 VPC의 격리 서브넷(인터넷 경로 없음)** 에
  붙여서, 그 서브넷 안에서 비공개 DNS(`parsing-engine.local`)로 엔진을 프라이빗하게
  부릅니다.
- `ENGINE_LAMBDA_SG_ID`는 Lambda에 붙이는 보안그룹인데, 엔진 쪽 보안그룹
  (`engine-sg`)이 **이 SG에서만** 8000번 포트 인바운드를 허용하도록 미리 잠가뒀습니다
  — 즉 이 값이 틀리면 Lambda가 엔진에 아예 연결이 안 됩니다(타임아웃).
- `ENGINE_BASE_URL`은 Cloud Map 사설 DNS 주소라 VPC 밖에서는 안 풀립니다 — 정상입니다.

## `npm ci` 실패 관련 (알려진 이슈)

이 저장소의 `flutter_app/package-lock.json`에 `@opentelemetry/core@2.0.0` 관련
불일치가 있어서 `npm ci`가 실패할 수 있습니다(`Missing: @opentelemetry/core@2.0.0
from lock file`). 2026-10-05 세션에서 확인된 바로는 **npm 버전 문제가 아니라
lock 파일 자체의 중첩 의존성 불일치**입니다(`COWORK_REPORTS.md` 참고). Cowork가
클라우드 임시 사본에서 lock을 재생성(`npm install`, 의존성 +8건)해서
`tsc --noEmit -p amplify` 오류 0건까지 확인했지만, 그 재생성된 lock 파일을 실제로
커밋할지는 아직 결정 안 됐습니다 — 지은 님이 로컬에서 `npm install`(ci 아님)로
한 번 lock을 재생성해보시고, diff가 합리적이면 그대로 커밋해 주세요. 괜찮아 보이면
팀 채널에 공유만 해주시면 됩니다.

## 샌드박스는 개인 환경입니다

지금 띄우는 건 지은 님 개인 AWS 계정의 sandbox입니다 — 팀 전체가 정식으로 쓰는
환경이 아닙니다. README에 적힌 대로, 출시 전에는 Amplify 콘솔에서 이 저장소의
`main` 브랜치를 연결해 공용 배포 환경을 따로 만들어야 하고, 그때는 위 4개 값도
그 공용 환경의 CI/CD 설정(예: Amplify 콘솔의 환경변수)에 다시 넣어줘야 합니다 —
지금 값은 엔진이 지금 이 AWS 계정(`220133863621`)에 떠 있는 동안만 유효합니다.

## 현재 엔진 상태

- 지금은 **테스트용으로 태스크 1개만 떠 있는 상태**입니다. 계속 켜둘지, 언제까지
  켜둘지는 별도로 상의가 필요합니다 — `RUNBOOK.md`에 끄는 방법 적어뒀습니다.
- 질문이나 문제가 있으면 `wishlist-appversion2/COWORK_REPORTS.md`의 가장 최근
  항목을 참고하거나 엔진 담당에게 물어봐 주세요.
