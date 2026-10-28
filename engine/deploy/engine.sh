#!/usr/bin/env bash
# 엔진 서버(parsing-engine)를 AWS ECS Fargate 에 올리고, 시연·테스트할 때만 켜고 끈다.
#
# 필요한 것: AWS CLI v2(로그인된 상태), Docker. 레포 어디서 실행해도 된다.
#
#   bash engine.sh setup     # 처음 한 번: 네트워크·저장소·권한·클러스터 만들기 (Gemini 키를 물어봄)
#   bash engine.sh deploy    # 코드를 바꿨을 때: 이미지 빌드·업로드 → 새 버전으로 교체 (켜져 있지 않으면 꺼진 채로)
#   bash engine.sh start     # 켜기 (1~3분)   — 켜져 있는 동안만 요금이 나간다(2 vCPU·4GB 기준 시간당 약 0.1달러)
#   bash engine.sh stop      # 끄기          — 시연이 끝나면 꼭 끌 것
#   bash engine.sh status    # 켜져 있는지 확인
#   bash engine.sh env       # Amplify 콘솔 환경변수에 넣을 값 출력
#   bash engine.sh destroy   # 전부 지우기 (Gemini 키 포함)
#
# 구성 (비용을 줄이려고 로드밸런서·NAT 게이트웨이를 쓰지 않는다):
#   - 기본 VPC 의 퍼블릭 서브넷에 태스크 1개. 퍼블릭 IP 를 받아서 Gemini·쇼핑몰에 직접 나간다.
#   - 들어오는 연결은 parsing-proxy Lambda 의 보안그룹에서 8000번 포트만 허용(인터넷에서는 못 들어옴).
#   - 주소는 Cloud Map 내부 DNS(engine.wishkit.local) — 껐다 켜서 IP 가 바뀌어도 Lambda 설정은 그대로.
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
NAME="wishkit-engine"
CPU=2048          # 2 vCPU — docs/reports/2026-09-24-fargate-validation.md 에서 검증한 크기
# 앱 → AppSync → parsing-proxy → 엔진. AppSync 가 30초까지만 기다려서 엔진 쪽 한도를 25초로 둔다(태스크 환경변수).
MEMORY=4096       # 4 GB
PORT=8000
NAMESPACE="wishkit.local"
DISCOVERY_SERVICE="engine"
GEMINI_KEY_PARAM="/wishkit/engine/GEMINI_API_KEY"

SERVER_DIR="$(cd "$(dirname "$0")/../server" && pwd)"
aws_() { aws --region "$REGION" "$@"; }
log() { echo "▶ $*"; }
none_to_empty() { [ "$1" = "None" ] && echo "" || echo "$1"; }

account_id() { aws sts get-caller-identity --query Account --output text; }
ecr_uri() { echo "$(account_id).dkr.ecr.${REGION}.amazonaws.com/${NAME}"; }

die() { echo "❌ $*" >&2; exit 1; }

# 필요한 프로그램·AWS 로그인이 있는지 맨 먼저 확인한다(없으면 중간에 엉뚱한 오류로 멈추지 않게).
preflight() {
  command -v aws >/dev/null 2>&1 ||
    die "AWS CLI 가 없어요. 설치: curl https://awscli.amazonaws.com/AWSCLIV2.pkg -o /tmp/AWSCLIV2.pkg && sudo installer -pkg /tmp/AWSCLIV2.pkg -target /"
  local who
  who=$(aws sts get-caller-identity --query Arn --output text 2>&1) ||
    die "AWS 로그인 정보가 없거나 잘못됐어요(aws configure 확인): $who"
  echo "▶ AWS 계정: $who" >&2
  if [ "${1:-}" = deploy ]; then
    command -v docker >/dev/null 2>&1 ||
      die "Docker 가 없어요. Docker Desktop 을 설치·실행하고, 그래도 안 되면 PATH 에 /Applications/Docker.app/Contents/Resources/bin 추가"
    docker info >/dev/null 2>&1 || die "Docker Desktop 이 꺼져 있어요. 앱을 켜고 고래 아이콘이 멈춘 뒤 다시 실행해 주세요."
  fi
}

default_vpc() {
  local vpc
  # 권한 오류 등은 그 내용을 그대로 보여 준다("VPC 가 없다"로 잘못 안내하지 않게).
  vpc=$(aws_ ec2 describe-vpcs --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text 2>&1) || die "VPC 조회 실패: $vpc"
  vpc=$(none_to_empty "$vpc")
  [ -n "$vpc" ] || die "기본 VPC 가 없어요. VPC 콘솔에서 '기본 VPC 생성'을 먼저 해 주세요."
  echo "$vpc"
}

subnets_csv() {
  aws_ ec2 describe-subnets --filters "Name=vpc-id,Values=$1" Name=default-for-az,Values=true \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ','
}

sg_id() {  # $1=vpc $2=이름 — 없으면 빈 값
  none_to_empty "$(aws_ ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$1" "Name=group-name,Values=$2" \
    --query 'SecurityGroups[0].GroupId' --output text)"
}

ensure_sg() {  # $1=vpc $2=이름 $3=설명 → GroupId
  local id
  id=$(sg_id "$1" "$2")
  if [ -z "$id" ]; then
    id=$(aws_ ec2 create-security-group --vpc-id "$1" --group-name "$2" --description "$3" \
      --query GroupId --output text)
  fi
  echo "$id"
}

namespace_id() {
  none_to_empty "$(aws_ servicediscovery list-namespaces \
    --query "Namespaces[?Name=='${NAMESPACE}'].Id | [0]" --output text)"
}

discovery_service_arn() {
  none_to_empty "$(aws_ servicediscovery list-services \
    --filters "Name=NAMESPACE_ID,Values=$1,Condition=EQ" \
    --query "Services[?Name=='${DISCOVERY_SERVICE}'].Arn | [0]" --output text)"
}

service_exists() {
  [ "$(aws_ ecs describe-services --cluster "$NAME" --services "$NAME" \
    --query 'services[?status==`ACTIVE`] | length(@)' --output text 2>/dev/null || echo 0)" = "1" ]
}

cmd_setup() {
  local vpc lambda_sg task_sg ns op
  vpc=$(default_vpc)
  log "보안그룹 (Lambda → 엔진 8000번만 허용)"
  lambda_sg=$(ensure_sg "$vpc" "${NAME}-lambda-sg" "parsing-proxy Lambda (no inbound)")
  task_sg=$(ensure_sg "$vpc" "${NAME}-task-sg" "engine task: 8000 from parsing-proxy Lambda only")
  aws_ ec2 authorize-security-group-ingress --group-id "$task_sg" --protocol tcp --port "$PORT" \
    --source-group "$lambda_sg" >/dev/null 2>&1 || true  # 이미 있으면 무시

  log "이미지 저장소(ECR) — 최근 5개 이미지만 남김"
  aws_ ecr create-repository --repository-name "$NAME" >/dev/null 2>&1 || true
  aws_ ecr put-lifecycle-policy --repository-name "$NAME" --lifecycle-policy-text \
    '{"rules":[{"rulePriority":1,"description":"keep last 5","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":5},"action":{"type":"expire"}}]}' >/dev/null

  log "로그 (14일 보관)"
  aws_ logs create-log-group --log-group-name "/ecs/${NAME}" >/dev/null 2>&1 || true
  aws_ logs put-retention-policy --log-group-name "/ecs/${NAME}" --retention-in-days 14

  log "실행 권한(IAM 역할)"
  aws iam create-role --role-name "${NAME}-exec-role" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    >/dev/null 2>&1 || true
  aws iam attach-role-policy --role-name "${NAME}-exec-role" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
  aws iam put-role-policy --role-name "${NAME}-exec-role" --policy-name read-gemini-key --policy-document \
    "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"ssm:GetParameters\",\"Resource\":\"arn:aws:ssm:${REGION}:$(account_id):parameter${GEMINI_KEY_PARAM}\"}]}"

  if ! aws_ ssm get-parameter --name "$GEMINI_KEY_PARAM" >/dev/null 2>&1; then
    log "Gemini API 키 저장 (암호화된 SSM 파라미터 — 이미지·코드에는 들어가지 않음)"
    local key
    read -r -s -p "GEMINI_API_KEY 붙여 넣기: " key; echo
    [ -n "$key" ] || { echo "키가 비어 있어요." >&2; exit 1; }
    aws_ ssm put-parameter --name "$GEMINI_KEY_PARAM" --type SecureString --value "$key" >/dev/null
  fi

  log "클러스터"
  aws_ ecs create-cluster --cluster-name "$NAME" >/dev/null

  log "내부 주소(Cloud Map: ${DISCOVERY_SERVICE}.${NAMESPACE})"
  ns=$(namespace_id)
  if [ -z "$ns" ]; then
    op=$(aws_ servicediscovery create-private-dns-namespace --name "$NAMESPACE" --vpc "$vpc" \
      --query OperationId --output text)
    for _ in $(seq 1 60); do
      [ "$(aws_ servicediscovery get-operation --operation-id "$op" --query Operation.Status --output text)" = "SUCCESS" ] && break
      sleep 5
    done
    ns=$(namespace_id)
    [ -n "$ns" ] || { echo "내부 주소 만들기가 끝나지 않았어요. 잠시 뒤 setup 을 다시 실행해 주세요." >&2; exit 1; }
  fi
  if [ -z "$(discovery_service_arn "$ns")" ]; then
    aws_ servicediscovery create-service --name "$DISCOVERY_SERVICE" --namespace-id "$ns" \
      --dns-config 'RoutingPolicy=MULTIVALUE,DnsRecords=[{Type=A,TTL=10}]' \
      --health-check-custom-config FailureThreshold=1 >/dev/null
  fi

  log "준비 끝. 다음: bash $0 deploy"
}

# 태스크 정의 JSON. macOS 기본 bash(3.2)는 $( ) 안의 heredoc 에서 괄호를 잘못 읽는 버그가 있어 함수로 뺐다.
task_def_json() {  # $1=이미지 주소:태그
  cat <<JSON
{
  "family": "${NAME}",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "${CPU}",
  "memory": "${MEMORY}",
  "executionRoleArn": "arn:aws:iam::$(account_id):role/${NAME}-exec-role",
  "containerDefinitions": [{
    "name": "engine",
    "image": "$1",
    "essential": true,
    "portMappings": [{"containerPort": ${PORT}, "protocol": "tcp"}],
    "secrets": [{"name": "GEMINI_API_KEY", "valueFrom": "${GEMINI_KEY_PARAM}"}],
    "environment": [
      {"name": "EXTRACT_TIMEOUT_S", "value": "25"},
      {"name": "RENDER_NAV_TIMEOUT_MS", "value": "12000"},
      {"name": "IDENTIFY_TIMEOUT_S", "value": "25"}
    ],
    "healthCheck": {
      "command": ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${PORT}/healthz', timeout=3)\""],
      "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 30
    },
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {"awslogs-group": "/ecs/${NAME}", "awslogs-region": "${REGION}", "awslogs-stream-prefix": "engine"}
    }
  }]
}
JSON
}

cmd_deploy() {
  local uri tag task_def_arn vpc ns registry
  uri=$(ecr_uri)
  # 커밋 해시 + 시각: 같은 커밋을 다시 배포해도 태그가 겹치지 않게(ECS 가 옛 이미지를 계속 쓰는 일 방지).
  tag="$(git -C "$SERVER_DIR" rev-parse --short HEAD 2>/dev/null || echo local)-$(date +%Y%m%d%H%M%S)"
  log "이미지 빌드·업로드 (${uri}:${tag}) — 서버는 x86 이라 linux/amd64 로 빌드"
  aws_ ecr get-login-password | docker login --username AWS --password-stdin "${uri%%/*}" >/dev/null
  docker buildx build --platform linux/amd64 -t "${uri}:${tag}" --push "$SERVER_DIR"

  log "태스크 정의 등록"
  task_def_arn=$(aws_ ecs register-task-definition --cli-input-json "$(task_def_json "${uri}:${tag}")" \
    --query taskDefinition.taskDefinitionArn --output text)

  if service_exists; then
    log "서비스를 새 버전으로 교체 (켜져 있었으면 새 버전으로 다시 뜨고, 꺼져 있었으면 꺼진 채)"
    aws_ ecs update-service --cluster "$NAME" --service "$NAME" --task-definition "$task_def_arn" >/dev/null
  else
    log "서비스 만들기 (꺼진 상태로 시작 — 켜려면 start)"
    vpc=$(default_vpc)
    ns=$(namespace_id)
    registry=$(discovery_service_arn "$ns")
    [ -n "$registry" ] || { echo "setup 을 먼저 실행해 주세요." >&2; exit 1; }
    aws_ ecs create-service --cluster "$NAME" --service-name "$NAME" --task-definition "$task_def_arn" \
      --desired-count 0 --launch-type FARGATE \
      --network-configuration "awsvpcConfiguration={subnets=[$(subnets_csv "$vpc")],securityGroups=[$(sg_id "$vpc" "${NAME}-task-sg")],assignPublicIp=ENABLED}" \
      --service-registries "registryArn=${registry}" >/dev/null
  fi
  log "배포 끝."
}

cmd_start() {
  service_exists || { echo "deploy 를 먼저 실행해 주세요." >&2; exit 1; }
  log "켜는 중… (1~3분)"
  aws_ ecs update-service --cluster "$NAME" --service "$NAME" --desired-count 1 >/dev/null
  aws_ ecs wait services-stable --cluster "$NAME" --services "$NAME"
  log "켜졌어요. 시연이 끝나면 꼭: bash $0 stop"
}

cmd_stop() {
  service_exists || { echo "서비스가 없어요(이미 지웠거나 deploy 전)."; return 0; }
  aws_ ecs update-service --cluster "$NAME" --service "$NAME" --desired-count 0 >/dev/null
  log "끄는 중… 몇십 초 뒤 요금이 멈춰요."
}

cmd_status() {
  if ! service_exists; then echo "서비스 없음 (deploy 전)"; return 0; fi
  aws_ ecs describe-services --cluster "$NAME" --services "$NAME" \
    --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}' --output table
  echo "desired=1 이고 running=1 이면 켜진 상태(요금 나가는 중), desired=0 이면 꺼진 상태"
}

cmd_env() {
  local vpc
  vpc=$(default_vpc)
  cat <<EOF
Amplify 콘솔 → 앱 → Hosting → Environment variables 에 아래 네 개를 넣고, ENGINE_DISABLED 는 지운 뒤 다시 배포하세요.

ENGINE_VPC_ID=${vpc}
ENGINE_PRIVATE_SUBNET_IDS=$(subnets_csv "$vpc")
ENGINE_LAMBDA_SG_ID=$(sg_id "$vpc" "${NAME}-lambda-sg")
ENGINE_BASE_URL=http://${DISCOVERY_SERVICE}.${NAMESPACE}:${PORT}
EOF
}

cmd_destroy() {
  read -r -p "엔진 관련 AWS 리소스를 전부 지울까요? Gemini 키도 지워집니다. (yes 입력) " ok
  [ "$ok" = "yes" ] || { echo "취소했어요."; return 0; }
  local vpc ns svc
  vpc=$(default_vpc)
  if service_exists; then
    aws_ ecs update-service --cluster "$NAME" --service "$NAME" --desired-count 0 >/dev/null
    aws_ ecs delete-service --cluster "$NAME" --service "$NAME" --force >/dev/null
    aws_ ecs wait services-inactive --cluster "$NAME" --services "$NAME"
  fi
  aws_ ecs delete-cluster --cluster "$NAME" >/dev/null 2>&1 || true
  ns=$(namespace_id)
  if [ -n "$ns" ]; then
    svc=$(discovery_service_arn "$ns")
    [ -n "$svc" ] && aws_ servicediscovery delete-service --id "${svc##*/}" >/dev/null 2>&1 || true
    aws_ servicediscovery delete-namespace --id "$ns" >/dev/null 2>&1 || true
  fi
  aws_ ecr delete-repository --repository-name "$NAME" --force >/dev/null 2>&1 || true
  aws_ logs delete-log-group --log-group-name "/ecs/${NAME}" >/dev/null 2>&1 || true
  aws_ ssm delete-parameter --name "$GEMINI_KEY_PARAM" >/dev/null 2>&1 || true
  aws iam delete-role-policy --role-name "${NAME}-exec-role" --policy-name read-gemini-key >/dev/null 2>&1 || true
  aws iam detach-role-policy --role-name "${NAME}-exec-role" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null 2>&1 || true
  aws iam delete-role --role-name "${NAME}-exec-role" >/dev/null 2>&1 || true
  for sg in "${NAME}-task-sg" "${NAME}-lambda-sg"; do
    local id
    id=$(sg_id "$vpc" "$sg")
    # Lambda 보안그룹은 Amplify 백엔드가 아직 쓰고 있으면 지워지지 않는다(정상) — 백엔드에서 엔진 설정을 뺀 뒤 다시 실행.
    [ -n "$id" ] && { aws_ ec2 delete-security-group --group-id "$id" >/dev/null 2>&1 || echo "  보안그룹 $sg 은(는) 아직 사용 중이라 남겨 뒀어요."; }
  done
  log "정리 끝."
}

case "${1:-}" in
  setup | deploy | start | stop | status | env | destroy) preflight "$1" ;;
esac

case "${1:-}" in
  setup) cmd_setup ;;
  deploy) cmd_deploy ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  env) cmd_env ;;
  destroy) cmd_destroy ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
