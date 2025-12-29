# Troubleshooting

This file lists common issues for this project and the simplest way to fix them.

## Deploy script fails with “Invalid endpoint: https://ecs..amazonaws.com”

This means the AWS region is empty. The CLI builds an endpoint from the region, so a missing region produces an invalid URL.

Fix: source the environment file and confirm the region is set.

'source scripts/env.sh'
'echo "$AWS_REGION"'

If you use a new terminal, you must source env.sh again before running scripts.

## ECS cluster is INACTIVE and deploy fails with ClusterNotFoundException

If a cluster was deleted earlier, ECS may show it as INACTIVE. You cannot update a service in an inactive cluster.

Fix: the deploy script should recreate the cluster when it sees INACTIVE. If needed, delete and recreate manually.

'aws ecs delete-cluster --region "$AWS_REGION" --cluster "$CLUSTER_NAME" || true'
'aws ecs create-cluster --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME"'

## The deploy script “hangs” or looks stuck

Most of the time it is waiting on AWS operations. Typical waits are: ALB provisioning, ECS service becoming stable, or ECR pushing layers.

Fix: open a second terminal and check progress.

'aws ecs describe-services --region "$AWS_REGION" --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --query 'services[0].events[0:10].[createdAt,message]' --output table'

You can also check target health.

'TG_ARN="$(aws elbv2 describe-target-groups --region "$AWS_REGION" --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text)"'
'aws elbv2 describe-target-health --region "$AWS_REGION" --target-group-arn "$TG_ARN" --output table'

## Targets are in “draining” state

This usually happens during a deployment or when a task was stopped. The ALB is removing old targets gracefully.

Fix: wait a short time and re-check target health.

'aws elbv2 describe-target-health --region "$AWS_REGION" --target-group-arn "$TG_ARN" --output table'

## ALB health check fails

Common reasons are wrong container port, wrong health path, or security group rules.

Fix: confirm the service listens on the same port as the target group and that the health path is correct.

Check that the Node app listens on port 3000 and the target group uses port 3000 with path /health.

Also confirm the ECS security group allows inbound from the ALB security group to port 3000.

## curl returns 502 or 503 from the ALB

This means the ALB cannot reach any healthy targets.

Fix: check target health and ECS task status.

'aws ecs list-tasks --region "$AWS_REGION" --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" --desired-status RUNNING --output text'
'aws elbv2 describe-target-health --region "$AWS_REGION" --target-group-arn "$TG_ARN" --output table'

## Cleanup does not remove everything

If something is still in use, AWS may delay deletion. For example, security groups can fail to delete if still attached.

Fix: run destroy again, then run verify in destroyed mode.

'./scripts/destroy.sh'
'./scripts/verify.sh destroyed'

If a resource still exists, find it by name and delete it manually from AWS or with the CLI.
