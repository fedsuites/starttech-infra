# StartTech Architecture Documentation

## Overview

StartTech is a full-stack Todo application deployed on AWS using a microservices-inspired architecture with automated CI/CD pipelines, auto-scaling, and centralized monitoring.

## Architecture Diagram
                             ┌──────────────────────────────────────────┐
                             │                   AWS Cloud               │
                             │                                           │
Users ──► CloudFront ──► S3   │   (React Static Frontend)                │
CDN          Bucket│                                           │
│                                           │
Users ──► Route53 (optional)  │                                           │
│                  │                                           │
▼                  │                                           │
┌─────────┐              │                                           │
│   ALB   │              │                                           │
└────┬────┘              │                                           │
│                  │                                           │
┌───────┴────────┐         │                                           │
│  Auto Scaling  │         │                                           │
│    Group       │         │                                           │
│  ┌──────────┐  │         │                                           │
│  │  EC2 #1  │  │         │                                           │
│  │ (Docker) │  │         │                                           │
│  └──────────┘  │         │                                           │
│  ┌──────────┐  │         │                                           │
│  │  EC2 #2  │  │         │                                           │
│  │ (Docker) │  │         │                                           │
│  └──────────┘  │         │                                           │
└───────┬────────┘         │                                           │
│                  │                                           │
┌───────┴────────┐         │                                           │
│                │         │                                           │
┌────▼────┐    ┌──────▼──────┐  │                                           │
│ElastiCache│  │ MongoDB Atlas│  │                                           │
│  Redis   │  │  (External)  │  │                                           │
└──────────┘  └─────────────┘  │                                           │
│                                           │
CloudWatch Logs & Metrics│                                           │
└──────────────────────────────────────────┘

## Components

### Frontend
- **Technology**: React 19, Vite, TypeScript, TailwindCSS
- **Hosting**: AWS S3 static website hosting
- **CDN**: AWS CloudFront for global content delivery
- **Build**: Vite production bundle output to `Client/dist/`
- **Environment**: `VITE_API_BASE_URL` points to ALB DNS

### Backend API
- **Technology**: Golang, Gin framework
- **Containerized**: Docker image stored in AWS ECR
- **Hosting**: EC2 instances inside an Auto Scaling Group
- **Entry point**: `Server/MuchToDo/cmd/api/main.go`
- **Port**: 8080
- **Health endpoint**: `GET /health`

### Load Balancer
- **Type**: AWS Application Load Balancer (ALB)
- **Listeners**: HTTP on port 80
- **Target Group**: EC2 instances on port 8080
- **Health checks**: `GET /health` every 30 seconds

### Auto Scaling Group
- **Min instances**: 1
- **Max instances**: 4
- **Desired**: 2
- **Scale up**: CPU > 70% for 2 consecutive periods
- **Scale down**: CPU < 20% for 2 consecutive periods
- **Update strategy**: Rolling update with 50% minimum healthy

### Database
- **Technology**: MongoDB Atlas (cloud-hosted)
- **Connection**: Via `MONGO_URI` environment variable
- **Driver**: `go.mongodb.org/mongo-driver`

### Cache
- **Technology**: AWS ElastiCache Redis 7.1
- **Node type**: cache.t3.micro
- **Purpose**: Session caching, API response caching
- **Connection**: Via `REDIS_ADDR` environment variable

### Container Registry
- **Technology**: AWS ECR
- **Repository**: `starttech-backend`
- **Tagging**: Git SHA for each build, `latest` always points to most recent
- **Scanning**: Trivy vulnerability scanning on every push
- **Lifecycle**: Keep last 10 images

## Networking

### VPC Layout
VPC (10.0.0.0/16)
├── Public Subnets
│   ├── 10.0.1.0/24 (AZ-1) — ALB
│   └── 10.0.2.0/24 (AZ-2) — ALB
└── Private Subnets
├── 10.0.3.0/24 (AZ-1) — EC2, ElastiCache
└── 10.0.4.0/24 (AZ-2) — EC2, ElastiCache

### Security Groups

| Component | Inbound | Outbound |
|-----------|---------|----------|
| ALB | 80, 443 from 0.0.0.0/0 | All |
| EC2 | 8080 from ALB SG only | All |
| Redis | 6379 from EC2 SG only | All |

## CI/CD Architecture

### Infrastructure Pipeline (`starttech-infra`)
Push to main
│
▼
Terraform Plan
│
▼
Terraform Apply (auto on main)
│
▼
AWS Resources Created

### Frontend Pipeline (`much-to-do`)
Push to feature/full-stack (Client/ changes)
│
▼
Install deps → Lint → Security audit → Build
│
▼
Sync to S3 → Invalidate CloudFront

### Backend Pipeline (`much-to-do`)
Push to feature/full-stack (Server/ changes)
│
▼
Unit tests → Integration tests → Vulnerability scan
│
▼
Build Docker image → Trivy scan → Push to ECR
│
▼
Update Launch Template → ASG Instance Refresh
│
▼
Smoke test via ALB health check

## Monitoring

### CloudWatch Log Groups
| Log Group | Purpose |
|-----------|---------|
| `/starttech/backend` | Backend application logs |
| `/starttech/frontend` | Frontend access logs |
| `/starttech/infrastructure` | Infrastructure events |

### CloudWatch Alarms
| Alarm | Threshold | Action |
|-------|-----------|--------|
| CPU High | > 70% | Scale up ASG |
| CPU Low | < 20% | Scale down ASG |
| ALB 5XX Errors | > 10 per minute | SNS alert |
| ALB Response Time | > 2 seconds | SNS alert |
| Unhealthy Hosts | > 0 | SNS alert |
| Redis CPU High | > 70% | SNS alert |

## Security

### Secrets Management
- All secrets stored in GitHub Actions Secrets
- No secrets committed to version control
- EC2 instances use IAM roles — no hardcoded AWS credentials
- Environment variables injected at container runtime via `/etc/muchtodo/env`

### IAM Least Privilege
- EC2 role has only: ECR pull, CloudWatch logs, CloudWatch metrics
- CI/CD user has only: ECR push, S3 sync, CloudFront invalidation, ASG refresh

### Network Security
- EC2 instances in private subnets — not directly accessible from internet
- Only ALB is public-facing
- Redis accessible only from EC2 security group
- All inter-service communication stays within VPC