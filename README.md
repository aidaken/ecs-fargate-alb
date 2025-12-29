# ECS Fargate + ALB Demo Project

This project shows how to deploy a simple Node.js application to AWS using ECS Fargate and an Application Load Balancer.  
The goal of the project is to demonstrate how real cloud services work together without using frameworks like Terraform or CDK, only AWS CLI and Bash scripts.

The application runs in Docker containers, is managed by ECS Fargate, and is доступно from the internet through an Application Load Balancer.  
Health checks, automatic restarts, logging, and cleanup are all handled the same way as in real production systems.

---

## What this project does

This project builds a Docker image with a small Node.js server.  
The image is pushed to Amazon ECR.  
ECS Fargate runs two containers based on this image.  
An Application Load Balancer sends traffic to healthy containers only.  
If a container stops or fails a health check, ECS automatically replaces it.

All resources can also be fully deleted using one command.

---

## Application behavior

The application exposes two endpoints.

`/` returns `ok`  
`/health` returns `healthy`

The `/health` endpoint is used by the Load Balancer to decide if the container is healthy.

---

## Technologies used

The project uses AWS ECS with Fargate to run containers without managing servers.  
Application Load Balancer is used to expose the service to the internet.  
Amazon ECR stores Docker images.  
CloudWatch Logs stores container logs.  
IAM is used for execution roles and permissions.  

Docker is used to containerize the application.  
AWS CLI and Bash are used to create and manage all resources.

---

## Architecture overview

A user sends an HTTP request from the browser.  
The request goes to the Application Load Balancer on port 80.  
The Load Balancer forwards the request to the ECS Target Group.  
The Target Group sends traffic only to healthy Fargate tasks.  
Each task runs the Node.js container on port 3000.

The system automatically replaces unhealthy containers.

---

## Project structure

The `app` folder contains the Node.js server.  
The `docker` folder contains the Dockerfile.  
The `ecs` folder contains the ECS task definition template.  
The `iam` folder contains IAM policies and trust relationships.  
The `scripts` folder contains deploy, destroy, and verify scripts.  
The `docs` folder is for architecture and troubleshooting notes.

---

## How to deploy

Before starting, make sure AWS CLI, Docker, jq, and Bash are installed.  
AWS credentials must be configured using `aws configure` or environment variables.

Run the deploy script:

'./scripts/deploy.sh'

The script supposed to:
- Create ECR if it does not exist
- Build and push the Docker image
- Create IAM execution role
- Create CloudWatch log group
- Create ECS cluster if needed
- Create security groups
- Create Application Load Balancer
- Create Target Group and Listener
- Register task definition
- Create or update ECS service

At the end, the ALB DNS name will be printed.

---

## How to verify deployment

To check that everything is running:

'./scripts/verify.sh deployed'

You can also open the ALB DNS in the browser and test `/` and `/health`.

---

## Self-healing demonstration

If one ECS task is stopped manually, ECS will automatically start a new one.  
The Load Balancer will stop sending traffic to the stopped task and continue serving requests without downtime.

This behavior was tested during development :)

---

## How to destroy everything

To delete all created AWS resources:

'./scripts/destroy.sh'

To verify that everything was removed:

'./scripts/verify.sh destroyed'

No AWS resources should remain active after this.

---

## Security and personal data

This repository does not contain AWS access keys, secrets, passwords, or tokens:)
All sensitive values are resolved at runtime using AWS CLI and IAM roles.

---

## Why this project exists

This project was built as a learning and portfolio project.  
It shows ECS Fargate behavior, not a simplified example.  
It focuses on understanding how AWS services work together in practice.

---

## Author

Aidar Kenzhebaev
CS Student and Cloud Engineering enthusiast
