# StartTech Infrastructure

Infrastructure as Code (IaC) for the StartTech application stack, managed with Terraform and automated via GitHub Actions.

## Architecture Overview

```
                          ┌─────────────────┐
                          │   CloudFront    │
                          │      CDN        │
                          └────────┬────────┘
                                   │
                          ┌────────▼────────┐
                          │   S3 Bucket     │
                          │ (React Frontend)│
                          └─────────────────┘

Internet ──► ALB ──► Auto Scaling Group (EC2)
                              │
                    ┌─────────┴──────────┐
                    │                    │
             ┌──────▼──────┐    ┌───────▼───────┐
             │ ElastiCache │    │  MongoDB Atlas │
             │   (Redis)   │    │   (Database)   │
             └─────────────┘    └───────────────┘
```

## Repository Structure

```
starttech-infra/
├── .github/workflows/
│   └── infrastructure-deploy.yml  # CI/CD pipeline for Terraform
├── terraform/
│   ├── main.tf                    # Root module, IAM, provider config
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── terraform.tfvars.example   # Example variable values
│   └── modules/
│       ├── networking/            # VPC, subnets, security groups
│       ├── compute/               # EC2, ASG, ALB, ECR
│       ├── storage/               # S3, CloudFront, ElastiCache
│       └── monitoring/            # CloudWatch, SNS alarms
├── scripts/
│   └── deploy-infrastructure.sh  # Manual deployment script
├── monitoring/
│   ├── cloudwatch-dashboard.json  # Dashboard definition
│   ├── alarm-definitions.json     # Alarm configurations
│   └── log-insights-queries.txt  # Useful log queries
└── README.md
```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS account with permissions for: EC2, S3, CloudFront, ElastiCache, CloudWatch, IAM, ECR

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/fedsuites/starttech-infra.git
cd starttech-infra
```

### 2. Configure variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Set up AWS credentials

```bash
export AWS_ACCESS_KEY_ID=your-access-key
export AWS_SECRET_ACCESS_KEY=your-secret-key
export AWS_REGION=us-east-1
```

### 4. Deploy infrastructure

```bash
# Plan first
chmod +x scripts/deploy-infrastructure.sh
./scripts/deploy-infrastructure.sh plan

# Apply
./scripts/deploy-infrastructure.sh apply
```

## GitHub Actions Pipeline

The infrastructure pipeline triggers automatically on pushes to `main` that modify Terraform files.

### Required GitHub Secrets

Set these in your repo under Settings → Secrets → Actions:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_REGION` | AWS region e.g. `us-east-1` |
| `S3_BUCKET_NAME` | Unique S3 bucket name for frontend |
| `ALARM_EMAIL` | Email for CloudWatch alarm notifications |

### Pipeline Stages

| Stage | Trigger | Action |
|-------|---------|--------|
| Plan | Every PR and push | `terraform plan` |
| Apply | Push to `main` | `terraform apply` |
| Destroy | Manual trigger only | `terraform destroy` |

## Terraform Modules

### Networking
- VPC with public and private subnets across 2 AZs
- Internet Gateway and NAT Gateway
- Security groups for ALB, EC2, and Redis

### Compute
- ECR repository for Docker images
- Application Load Balancer with health checks
- Launch Template with CloudWatch agent
- Auto Scaling Group with rolling updates
- Scale up at 70% CPU, scale down at 20% CPU

### Storage
- S3 bucket for React frontend with static website hosting
- CloudFront distribution with Origin Access Control
- ElastiCache Redis cluster for caching and sessions

### Monitoring
- CloudWatch Log Groups for backend, frontend, infrastructure
- CloudWatch Dashboard with key metrics
- SNS topic for alarm notifications
- Alarms for 5XX errors, response time, unhealthy hosts, CPU

## Infrastructure Outputs

After applying, Terraform outputs these values — add them as GitHub Secrets in the application repo:

| Output | GitHub Secret |
|--------|--------------|
| `alb_dns_name` | `ALB_DNS_NAME` |
| `cloudfront_distribution_id` | `CLOUDFRONT_DISTRIBUTION_ID` |
| `s3_bucket_name` | `S3_BUCKET_NAME` |
| `ecr_repository_url` | `ECR_REPOSITORY_URL` |

## Destroying Infrastructure

```bash
./scripts/deploy-infrastructure.sh destroy
```

Or trigger manually via GitHub Actions → workflow_dispatch → select `destroy`.

>  This will permanently delete all resources including the S3 bucket and database connections.
