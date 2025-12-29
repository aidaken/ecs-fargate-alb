#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/env.sh"

: "${AWS_REGION:?missing}"
: "${PROJECT_NAME:?missing}"
: "${CLUSTER_NAME:?missing}"
: "${SERVICE_NAME:?missing}"
: "${TASK_FAMILY:?missing}"
: "${ALB_NAME:?missing}"
: "${TG_NAME:?missing}"
: "${ALB_SG_NAME:?missing}"
: "${ECS_SG_NAME:?missing}"
: "${LOG_GROUP_NAME:?missing}"
: "${EXEC_ROLE_NAME:?missing}"
: "${EXEC_POLICY_NAME:?missing}"
: "${ECR_REPO_NAME:?missing}"
: "${CONTAINER_NAME:?missing}"
: "${CONTAINER_PORT:?missing}"
: "${HEALTH_PATH:?missing}"

export AWS_PAGER=""

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
IMAGE_TAG="$(date +%Y%m%d%H%M%S)"

echo "AWS_REGION=$AWS_REGION"
echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo "ECR_URI=$ECR_URI"
echo "IMAGE_TAG=$IMAGE_TAG"

aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO_NAME" >/dev/null 2>&1 \
|| aws ecr create-repository --region "$AWS_REGION" --repository-name "$ECR_REPO_NAME" >/dev/null

if aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP_NAME" \
  --query "logGroups[].logGroupName" --output text | tr '\t' '\n' | grep -Fxq "$LOG_GROUP_NAME"; then
  :
else
  aws logs create-log-group --region "$AWS_REGION" --log-group-name "$LOG_GROUP_NAME" >/dev/null
fi
aws logs put-retention-policy --region "$AWS_REGION" --log-group-name "$LOG_GROUP_NAME" --retention-in-days 7 >/dev/null

aws iam get-role --role-name "$EXEC_ROLE_NAME" >/dev/null 2>&1 \
|| aws iam create-role --role-name "$EXEC_ROLE_NAME" --assume-role-policy-document "file://${ROOT_DIR}/iam/trust-policy.json" >/dev/null

aws iam attach-role-policy \
  --role-name "$EXEC_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null 2>&1 || true

aws iam put-role-policy \
  --role-name "$EXEC_ROLE_NAME" \
  --policy-name "$EXEC_POLICY_NAME" \
  --policy-document "file://${ROOT_DIR}/iam/exec-inline-policy.json" >/dev/null

EXEC_ROLE_ARN="$(aws iam get-role --role-name "$EXEC_ROLE_NAME" --query 'Role.Arn' --output text)"
echo "EXEC_ROLE_ARN=$EXEC_ROLE_ARN"

aws ecr get-login-password --region "$AWS_REGION" \
| docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" >/dev/null

docker build -t "${ECR_REPO_NAME}:${IMAGE_TAG}" -f "${ROOT_DIR}/docker/Dockerfile" "${ROOT_DIR}"
docker tag "${ECR_REPO_NAME}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:${IMAGE_TAG}"
echo "Pushed image: ${ECR_URI}:${IMAGE_TAG}"

cluster_status="$(aws ecs describe-clusters --region "$AWS_REGION" --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null || true)"
if [[ "$cluster_status" == "INACTIVE" ]]; then
  aws ecs delete-cluster --region "$AWS_REGION" --cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true
  cluster_status=""
fi
if [[ -z "${cluster_status:-}" || "$cluster_status" == "None" ]]; then
  aws ecs create-cluster --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" >/dev/null
fi

VPC_ID="$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"

PUBLIC_SUBNET_IDS="$(
  aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]' \
    --output text | sort -k2 | awk '$3=="True"{print $1}' | head -n 2
)"

if [[ "$(echo "$PUBLIC_SUBNET_IDS" | wc -l | tr -d ' ')" -lt 2 ]]; then
  PUBLIC_SUBNET_IDS="$(
    aws ec2 describe-subnets \
      --region "$AWS_REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" \
      --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
      --output text | sort -k2 | awk '{print $1}' | head -n 2
  )"
fi

SUBNET_1="$(echo "$PUBLIC_SUBNET_IDS" | sed -n '1p')"
SUBNET_2="$(echo "$PUBLIC_SUBNET_IDS" | sed -n '2p')"

if [[ -z "${SUBNET_1:-}" || -z "${SUBNET_2:-}" ]]; then
  echo "FAIL: could not determine two subnets in default VPC"
  exit 1
fi

ALB_SG_ID="$(
  aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$ALB_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true
)"
if [[ -z "${ALB_SG_ID:-}" || "$ALB_SG_ID" == "None" ]]; then
  ALB_SG_ID="$(aws ec2 create-security-group --region "$AWS_REGION" --vpc-id "$VPC_ID" --group-name "$ALB_SG_NAME" --description "ALB SG" --query GroupId --output text)"
fi

ECS_SG_ID="$(
  aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$ECS_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true
)"
if [[ -z "${ECS_SG_ID:-}" || "$ECS_SG_ID" == "None" ]]; then
  ECS_SG_ID="$(aws ec2 create-security-group --region "$AWS_REGION" --vpc-id "$VPC_ID" --group-name "$ECS_SG_NAME" --description "ECS SG" --query GroupId --output text)"
fi

aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$ALB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=http}]" \
  >/dev/null 2>&1 || true

aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$ECS_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=${CONTAINER_PORT},ToPort=${CONTAINER_PORT},UserIdGroupPairs=[{GroupId=${ALB_SG_ID},Description=from-alb}]" \
  >/dev/null 2>&1 || true

TG_ARN="$(
  aws elbv2 describe-target-groups --region "$AWS_REGION" --names "$TG_NAME" \
    --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true
)"
if [[ -z "${TG_ARN:-}" || "$TG_ARN" == "None" ]]; then
  TG_ARN="$(aws elbv2 create-target-group \
    --region "$AWS_REGION" \
    --name "$TG_NAME" \
    --protocol HTTP \
    --port "$CONTAINER_PORT" \
    --vpc-id "$VPC_ID" \
    --target-type ip \
    --health-check-protocol HTTP \
    --health-check-path "$HEALTH_PATH" \
    --health-check-port traffic-port \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)"
fi

ALB_ARN="$(
  aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true
)"
if [[ -z "${ALB_ARN:-}" || "$ALB_ARN" == "None" ]]; then
  ALB_ARN="$(aws elbv2 create-load-balancer \
    --region "$AWS_REGION" \
    --name "$ALB_NAME" \
    --type application \
    --scheme internet-facing \
    --subnets "$SUBNET_1" "$SUBNET_2" \
    --security-groups "$ALB_SG_ID" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text)"
fi

ALB_DNS="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].DNSName' --output text)"

LISTENER_ARN="$(
  aws elbv2 describe-listeners --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" \
    --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text 2>/dev/null || true
)"
if [[ -z "${LISTENER_ARN:-}" || "$LISTENER_ARN" == "None" ]]; then
  LISTENER_ARN="$(aws elbv2 create-listener \
    --region "$AWS_REGION" \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
    --query 'Listeners[0].ListenerArn' \
    --output text)"
fi

tmp_taskdef="$(mktemp)"
sed -e "s|__EXEC_ROLE_ARN__|${EXEC_ROLE_ARN}|g" \
    -e "s|__IMAGE__|${ECR_URI}:${IMAGE_TAG}|g" \
    -e "s|__AWS_REGION__|${AWS_REGION}|g" \
    -e "s|__LOG_GROUP__|${LOG_GROUP_NAME}|g" \
    "${ROOT_DIR}/ecs/taskdef.json" > "$tmp_taskdef"

TASK_DEF_ARN="$(aws ecs register-task-definition --region "$AWS_REGION" --cli-input-json "file://$tmp_taskdef" --query 'taskDefinition.taskDefinitionArn' --output text)"
rm -f "$tmp_taskdef"
echo "TASK_DEF_ARN=$TASK_DEF_ARN"

SERVICE_STATUS="$(aws ecs describe-services --region "$AWS_REGION" --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --query 'services[0].status' --output text 2>/dev/null || true)"

NETWORK_CFG="awsvpcConfiguration={subnets=[\"$SUBNET_1\",\"$SUBNET_2\"],securityGroups=[\"$ECS_SG_ID\"],assignPublicIp=ENABLED}"

if [[ -z "${SERVICE_STATUS:-}" || "$SERVICE_STATUS" == "None" || "$SERVICE_STATUS" == "INACTIVE" ]]; then
  aws ecs create-service \
    --region "$AWS_REGION" \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count 2 \
    --launch-type FARGATE \
    --network-configuration "$NETWORK_CFG" \
    --load-balancers "targetGroupArn=$TG_ARN,containerName=$CONTAINER_NAME,containerPort=$CONTAINER_PORT" \
    >/dev/null
else
  aws ecs update-service \
    --region "$AWS_REGION" \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --desired-count 2 \
    --force-new-deployment \
    >/dev/null
fi

aws ecs wait services-stable --region "$AWS_REGION" --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"

echo "ALB_DNS=${ALB_DNS}"
curl -s -o /dev/null -w "health http_code=%{http_code}\n" "http://${ALB_DNS}${HEALTH_PATH}" || true
echo "done"

