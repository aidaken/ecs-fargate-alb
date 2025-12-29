# Architecture

This project deploys a small HTTP app to AWS ECS Fargate behind an Application Load Balancer (ALB). The app exposes two endpoints: `/` and `/health`. The ALB forwards traffic to ECS tasks and uses `/health` for health checks.

The goal is to show the full flow of a typical production-like setup: build a container image, push it to ECR, run it on Fargate, route traffic through an ALB, and collect logs in CloudWatch.

## What gets created

The deploy script creates or updates these resources in the selected AWS region:

An ECR repository where the Docker image is pushed.

A CloudWatch Log Group where the container logs are written.

An IAM execution role for the ECS task. This role allows the task to pull the image from ECR and write logs to CloudWatch.

An ECS cluster, service, and task definition for running the container on Fargate.

An Application Load Balancer with a listener on port 80.

A target group of type `ip` that registers the running Fargate task IPs.

Two security groups. The ALB security group allows inbound HTTP from the internet. The ECS security group allows inbound traffic only from the ALB security group to the container port.

The deploy script uses the default VPC and picks two public subnets where auto-assign public IPv4 is enabled. This is a simple setup that works for a demo without managing custom networking.

## Request flow

A client sends an HTTP request to the ALB DNS name.

The ALB listener on port 80 forwards the request to the target group.

The target group routes the request to one of the healthy ECS tasks.

The ECS task runs the Node.js server and responds.

## Health checks

The ALB target group runs health checks against the ECS tasks using the `/health` path. Only healthy targets receive traffic. When a task is stopped or replaced, the ALB will drain connections and deregister the target.

## Logging

The container uses the awslogs driver. Each task writes logs to the CloudWatch Log Group defined by the project. This includes the startup message and any request logs you add later.

## Self-healing behavior

The ECS service maintains the desired count. If you stop a running task, ECS will start a new one automatically. During this time the ALB keeps routing traffic only to healthy targets, so the service stays available.
