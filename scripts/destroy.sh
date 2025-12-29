#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?missing}"
: "${PROJECT_NAME:?missing}"
: "${CLUSTER_NAME:?missing}"
: "${SERVICE_NAME:?missing}"
: "${ALB_NAME:?missing}"
: "${TG_NAME:?missing}"
: "${ALB_SG_NAME:?missing}"
: "${ECS_SG_NAME:?missing}"
: "${LOG_GROUP_NAME:?missing}"
: "${EXEC_ROLE_NAME:?missing}"
: "${EXEC_POLICY_NAME:?missing}"
: "${ECR_REPO_NAME:?missing}"

export AWS_PAGER=""

aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --desired-count 0 >/dev/null 2>&1 || true

aws ecs delete-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --force >/dev/null 2>&1 || true

aws ecs wait services-inactive \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" >/dev/null 2>&1 || true

aws ecs delete-cluster \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true

ALB_ARN="$(
  aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --names "$ALB_NAME" \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null || true
)"
if [ -n "${ALB_ARN:-}" ] && [ "$ALB_ARN" != "None" ]; then
  LISTENER_ARN="$(
    aws elbv2 describe-listeners \
      --region "$AWS_REGION" \
      --load-balancer-arn "$ALB_ARN" \
      --query 'Listeners[0].ListenerArn' \
      --output text 2>/dev/null || true
  )"
  if [ -n "${LISTENER_ARN:-}" ] && [ "$LISTENER_ARN" != "None" ]; then
    aws elbv2 delete-listener --region "$AWS_REGION" --listener-arn "$LISTENER_ARN" >/dev/null 2>&1 || true
  fi

  aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN" >/dev/null 2>&1 || true

  aws elbv2 wait load-balancers-deleted --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN" >/dev/null 2>&1 || true
fi

TG_ARN="$(
  aws elbv2 describe-target-groups \
    --region "$AWS_REGION" \
    --names "$TG_NAME" \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || true
)"
if [ -n "${TG_ARN:-}" ] && [ "$TG_ARN" != "None" ]; then
  aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$TG_ARN" >/dev/null 2>&1 || true
fi

VPC_ID="$(
  aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' \
    --output text
)"

ALB_SG_ID="$(
  aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$ALB_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true
)"
ECS_SG_ID="$(
  aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$ECS_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true
)"

if [ -n "${ECS_SG_ID:-}" ] && [ "$ECS_SG_ID" != "None" ]; then
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$ECS_SG_ID" >/dev/null 2>&1 || true
fi
if [ -n "${ALB_SG_ID:-}" ] && [ "$ALB_SG_ID" != "None" ]; then
  aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$ALB_SG_ID" >/dev/null 2>&1 || true
fi

aws logs delete-log-group --region "$AWS_REGION" --log-group-name "$LOG_GROUP_NAME" >/dev/null 2>&1 || true

aws iam delete-role-policy --role-name "$EXEC_ROLE_NAME" --policy-name "$EXEC_POLICY_NAME" >/dev/null 2>&1 || true
aws iam detach-role-policy --role-name "$EXEC_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null 2>&1 || true
aws iam delete-role --role-name "$EXEC_ROLE_NAME" >/dev/null 2>&1 || true

aws ecr delete-repository --region "$AWS_REGION" --repository-name "$ECR_REPO_NAME" --force >/dev/null 2>&1 || true

echo "destroy complete"

