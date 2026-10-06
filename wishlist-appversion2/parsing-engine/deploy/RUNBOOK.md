# parsing-engine 운영 런북

대상: AWS 계정 `220133863621`, 리전 `ap-northeast-2`. 리소스 ID 전체는
`deploy_state.json`(커밋 안 됨, 로컬에만 있음) 참고.

## ① 태스크 끄기 / 다시 켜기

**끄기(과금 중지, 리소스는 남겨둠)**:
```bash
aws ecs update-service --cluster parsing-engine-cluster \
  --service parsing-engine-svc --desired-count 0 --region ap-northeast-2
```

**다시 켜기**:
```bash
aws ecs update-service --cluster parsing-engine-cluster \
  --service parsing-engine-svc --desired-count 1 --region ap-northeast-2
```

태스크가 뜨는 데 1~2분 걸립니다. 확인:
```bash
aws ecs list-tasks --cluster parsing-engine-cluster --region ap-northeast-2
```

**비밀(Gemini 키)을 바꾼 뒤 반영하려면** `update-service`만으로는 안 되고,
강제 재배포가 필요합니다(이미 실행 중인 태스크는 시작 시점 값을 그대로 씀):
```bash
aws ecs update-service --cluster parsing-engine-cluster \
  --service parsing-engine-svc --force-new-deployment --region ap-northeast-2
```

## ② 전체 삭제

`teardown.sh`가 `deploy_state.json`을 읽어서 **우리가 만든 리소스만** 지웁니다
(amplify-* 리소스는 건드리지 않음). 먼저 `--dry-run`으로 뭘 지울지 확인:
```bash
bash wishlist-appversion2/parsing-engine/deploy/teardown.sh --dry-run
```
실제로 지우려면 `--dry-run` 없이:
```bash
bash wishlist-appversion2/parsing-engine/deploy/teardown.sh
```
삭제 순서: 서비스 desired-count 0 → 서비스 삭제 → Cloud Map 서비스/네임스페이스 →
보안그룹 → 라우트 테이블 연결 해제/삭제 → 서브넷 → IGW 분리/삭제 → VPC. (ECR
이미지, 태스크 정의, 로그 그룹, IAM 역할, Secrets Manager 비밀은 비용이 거의
없어서 스크립트가 기본적으로 안 지웁니다 — 완전히 지우고 싶으면 스크립트 안의
해당 섹션 주석을 보고 수동으로.)

## ③ 로그 보는 법

```bash
# 최근 로그 스트림 찾기
aws logs describe-log-streams --log-group-name /ecs/parsing-engine \
  --region ap-northeast-2 --order-by LastEventTime --descending --max-items 3

# 그 스트림의 로그 보기
aws logs get-log-events --log-group-name /ecs/parsing-engine \
  --log-stream-name "<위에서 찾은 이름>" --region ap-northeast-2 --limit 50
```
로그 그룹 보존 기간은 7일입니다 — 그 이후는 자동 삭제됩니다.

## ④ 비용 확인

**지금 실행 중인 것 확인(과금 중인지)**:
```bash
aws ecs list-tasks --cluster parsing-engine-cluster --region ap-northeast-2
aws ecs list-services --cluster parsing-engine-cluster --region ap-northeast-2
```
`taskArns`/`serviceArns`가 비어있지 않으면 과금 중입니다.

**실제 청구 금액**: AWS 콘솔 → Billing and Cost Management → Cost Explorer에서
서비스별(ElasticContainerService, EC2-Other 등)로 필터링해서 확인하는 게 제일
정확합니다. CLI로 대략 보려면:
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '7 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY --metrics UnblendedCost \
  --filter '{"Tags":{"Key":"Project","Values":["wishkit-engine"]}}'
```
(이 계정에 `ce:GetCostAndUsage` 권한이 있는지는 별도 확인 필요 — 없으면 콘솔 사용.)

## 참고 — 단가(2026-10 기준, 서울 리전)

- Fargate: vCPU $0.04656/시간, 메모리 $0.00511/GB-시간
- 공인 IPv4(사용중): $0.005/시간
- 태스크 1개(2vCPU/4GB) 상시 기준 시간당 약 $0.119, 한 달 약 $87~88

상세 계산 근거는 `wishlist-appversion2/COWORK_REPORTS.md`의 "엔진 배포" 항목 참고.
