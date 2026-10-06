#!/usr/bin/env bash
# parsing-engine 네트워크/서비스 리소스 정리 스크립트.
# deploy_state.json에 기록된, "우리가 만든" 리소스만 지운다.
#
# ECR 이미지 / 태스크 정의 / CloudWatch 로그 그룹 / IAM 실행 역할 / Secrets Manager
# 비밀은 비용이 거의 없어서 여기서 안 지운다 — 완전히 지우고 싶으면 아래 "수동 삭제"
# 섹션을 보고 직접.
#
# 사용법:
#   bash teardown.sh --dry-run   # 뭘 지울지만 출력, 아무것도 안 건드림
#   bash teardown.sh             # 실제로 삭제
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$DIR/deploy_state.json"
REGION="ap-northeast-2"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

if [ ! -f "$STATE_FILE" ]; then
  echo "deploy_state.json이 없습니다 ($STATE_FILE) — 지울 리소스 ID를 모릅니다. 중단."
  exit 1
fi

jget() { jq -r "$1 // empty" "$STATE_FILE"; }

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    "$@"
  fi
}

SVC_NAME=$(jget '.resources.ecs_service.name')
CLUSTER=$(jget '.resources.ecs_service.cluster')
NS_ID=$(jget '.resources.cloud_map.namespace_id')
SVC_ID=$(jget '.resources.cloud_map.service_id')
LAMBDA_SG=$(jget '.resources.security_groups.lambda_sg.id')
ENGINE_SG=$(jget '.resources.security_groups.engine_sg.id')
NEG_SG=$(jget '.resources.security_groups.negative_test_sg.id')
PULL_SG=$(jget '.resources.security_groups.test_pull_sg.id')
PUB_RT=$(jget '.resources.route_tables.public_rt.id')
ISO_RT=$(jget '.resources.route_tables.isolated_rt.id')
PUB_A=$(jget '.resources.subnets.public_2a.id')
PUB_C=$(jget '.resources.subnets.public_2c.id')
ISO_A=$(jget '.resources.subnets.isolated_2a.id')
ISO_C=$(jget '.resources.subnets.isolated_2c.id')
IGW=$(jget '.resources.internet_gateway.id')
VPC=$(jget '.resources.vpc.id')

echo "=== 1. ECS 서비스 끄고 삭제 ==="
if [ -n "$SVC_NAME" ] && [ -n "$CLUSTER" ]; then
  run aws ecs update-service --cluster "$CLUSTER" --service "$SVC_NAME" --desired-count 0 --region "$REGION"
  run aws ecs delete-service --cluster "$CLUSTER" --service "$SVC_NAME" --region "$REGION"
  run aws ecs delete-cluster --cluster "$CLUSTER" --region "$REGION"
fi

echo "=== 2. Cloud Map 서비스/네임스페이스 삭제 ==="
if [ -n "$SVC_ID" ]; then
  run aws servicediscovery delete-service --id "$SVC_ID" --region "$REGION"
fi
if [ -n "$NS_ID" ]; then
  run aws servicediscovery delete-namespace --id "$NS_ID" --region "$REGION"
fi

echo "=== 3. 임시 테스트용 보안그룹 삭제(negative-test, test-pull) ==="
for sg in "$NEG_SG" "$PULL_SG"; do
  [ -n "$sg" ] && run aws ec2 delete-security-group --group-id "$sg" --region "$REGION"
done

echo "=== 4. engine-sg / lambda-sg 삭제 ==="
for sg in "$ENGINE_SG" "$LAMBDA_SG"; do
  [ -n "$sg" ] && run aws ec2 delete-security-group --group-id "$sg" --region "$REGION"
done

echo "=== 5. 라우트 테이블 연결 해제 + 삭제 ==="
for rt in "$PUB_RT" "$ISO_RT"; do
  [ -z "$rt" ] && continue
  if $DRY_RUN; then
    echo "[dry-run] disassociate + delete route table $rt"
  else
    ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "$rt" --region "$REGION" \
      --query "RouteTables[0].Associations[?Main!=\`true\`].RouteTableAssociationId" --output text)
    for a in $ASSOC_IDS; do
      aws ec2 disassociate-route-table --association-id "$a" --region "$REGION"
    done
    aws ec2 delete-route-table --route-table-id "$rt" --region "$REGION"
  fi
done

echo "=== 6. 서브넷 삭제 ==="
for sn in "$PUB_A" "$PUB_C" "$ISO_A" "$ISO_C"; do
  [ -n "$sn" ] && run aws ec2 delete-subnet --subnet-id "$sn" --region "$REGION"
done

echo "=== 7. IGW 분리 + 삭제 ==="
if [ -n "$IGW" ] && [ -n "$VPC" ]; then
  run aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC" --region "$REGION"
  run aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$REGION"
fi

echo "=== 8. VPC 삭제 ==="
[ -n "$VPC" ] && run aws ec2 delete-vpc --vpc-id "$VPC" --region "$REGION"

echo ""
echo "=== 수동 삭제(비용 미미, 이 스크립트는 안 지움) ==="
echo "- ECR 이미지: aws ecr delete-repository --repository-name parsing-engine --force --region $REGION"
echo "- 태스크 정의: aws ecs deregister-task-definition --task-definition parsing-engine:<revision> --region $REGION"
echo "- 로그 그룹: aws logs delete-log-group --log-group-name /ecs/parsing-engine --region $REGION"
echo "- IAM 역할: aws iam detach-role-policy ... 후 aws iam delete-role --role-name parsing-engine-exec-role"
echo "- Secrets Manager 비밀: aws secretsmanager delete-secret --secret-id parsing-engine/gemini-api-key --region $REGION (기본 7일 유예기간)"

if $DRY_RUN; then
  echo ""
  echo "dry-run 끝 — 아무것도 실제로 지우지 않았습니다."
fi
