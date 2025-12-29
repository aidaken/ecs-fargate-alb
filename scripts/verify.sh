#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
if [[ "$mode" != "deployed" && "$mode" != "destroyed" ]]; then
  echo "usage: ./scripts/verify.sh deployed|destroyed"
  exit 1
fi
if [[ -z "${PROJECT_NAME:-}" || -z "${AWS_REGION:-}" ]]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"
fi
export AWS_PAGER=""
if [[ "$mode" == "destroyed" ]]; then
  echo "--- Checking cleanup status ---"
  aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" >/dev/null 2>&1 && { echo "FAIL: ALB exists"; exit 1; } || echo "OK: ALB deleted"
  aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPO_NAME" >/dev/null 2>&1 && { echo "FAIL: ECR exists"; exit 1; } || echo "OK: ECR deleted"
  if aws logs describe-log-groups --region "$AWS_REGION" --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[].logGroupName" --output text | tr '\t' '\n' | grep -Fxq "$LOG_GROUP_NAME"; then
    echo "FAIL: log group exists"
    exit 1
  else
    echo "OK: log group deleted"
  fi
  cluster_status="$(aws ecs describe-clusters --region "$AWS_REGION" --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null || true)"
  [[ "$cluster_status" == "ACTIVE" ]] && { echo "FAIL: cluster ACTIVE"; exit 1; } || echo "OK: cluster not ACTIVE"
  exit 0
fi
if [[ "$mode" == "deployed" ]]; then
  echo "--- Checking deployed status ---"
  aws elbv2 describe-load-balancers --region "$AWS_REGION" --names "$ALB_NAME" >/dev/null 2>&1 && echo "OK: ALB exists" || echo "FAIL: ALB missing"
  aws ecs describe-clusters --region "$AWS_REGION" --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text
  exit 0
fi
