# StartTech Operations Runbook

## Table of Contents
1. [Initial Setup](#initial-setup)
2. [Deploying Infrastructure](#deploying-infrastructure)
3. [Deploying the Application](#deploying-the-application)
4. [Monitoring](#monitoring)
5. [Scaling](#scaling)
6. [Rollback Procedures](#rollback-procedures)
7. [Troubleshooting](#troubleshooting)
8. [Disaster Recovery](#disaster-recovery)

---

## 1. Initial Setup

### Prerequisites
- AWS CLI installed and configured
- Terraform >= 1.5.0 installed
- GitHub account with access to both repos
- MongoDB Atlas account

### AWS IAM User Setup
1. Go to AWS Console → IAM → Users → Create User
2. Name it `starttech-cicd`
3. Attach these policies:
   - `AmazonEC2FullAccess`
   - `AmazonS3FullAccess`
   - `AmazonECR_FullAccess`
   - `CloudFrontFullAccess`
   - `AmazonElastiCacheFullAccess`
   - `CloudWatchFullAccess`
   - `IAMFullAccess`
   - `AmazonVPCFullAccess`
4. Generate access keys and save them

### MongoDB Atlas Setup
1. Go to [MongoDB Atlas](https://cloud.mongodb.com)
2. Create a free M0 cluster
3. Create a database user with read/write access
4. Whitelist `0.0.0.0/0` for EC2 access
5. Get the connection string — replace `<password>` with your password:
mongodb+srv://<user>:<password>@cluster0.xxxxx.mongodb.net/much_todo_db

### Create Terraform State Bucket
Run this ONCE before any Terraform commands:
```bash
aws s3 mb s3://starttech-terraform-state --region us-east-1
aws s3api put-bucket-versioning \
  --bucket starttech-terraform-state \
  --versioning-configuration Status=Enabled
```

### GitHub Secrets Setup

**For `starttech-infra` repo:**

| Secret | Where to get it |
|--------|----------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | e.g. `us-east-1` |
| `S3_BUCKET_NAME` | e.g. `starttech-frontend-prod` |
| `ALARM_EMAIL` | Your email address |

**For `much-to-do` repo (add after Terraform apply):**

| Secret | Where to get it |
|--------|----------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | e.g. `us-east-1` |
| `S3_BUCKET_NAME` | Terraform output: `s3_bucket_name` |
| `CLOUDFRONT_DISTRIBUTION_ID` | Terraform output: `cloudfront_distribution_id` |
| `VITE_API_BASE_URL` | `http://` + Terraform output: `alb_dns_name` |
| `ALB_DNS_NAME` | Terraform output: `alb_dns_name` |

---

## 2. Deploying Infrastructure

### First Time Deployment
```bash
cd starttech-infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

### Via GitHub Actions
1. Push any change to `terraform/` on the `main` branch
2. Pipeline runs `terraform plan` automatically
3. On merge to `main`, `terraform apply` runs automatically
4. To destroy, go to Actions → infrastructure-deploy → Run workflow → select `destroy`

### Collecting Terraform Outputs
After apply completes:
```bash
terraform output alb_dns_name
terraform output cloudfront_distribution_id
terraform output s3_bucket_name
terraform output ecr_repository_url
```

---

## 3. Deploying the Application

### First Time — EC2 Environment File
SSH into each EC2 instance and create `/etc/muchtodo/env`:
```bash
sudo mkdir -p /etc/muchtodo
sudo tee /etc/muchtodo/env << EOF
PORT=8080
MONGO_URI=mongodb+srv://user:pass@cluster0.xxxxx.mongodb.net/much_todo_db
DB_NAME=much_todo_db
JWT_SECRET_KEY=your-long-random-secret-key
JWT_EXPIRATION_HOURS=72
ENABLE_CACHE=true
REDIS_ADDR=<elasticache-endpoint>:6379
LOG_LEVEL=INFO
LOG_FORMAT=json
ALLOWED_ORIGINS=https://<cloudfront-domain>
COOKIE_DOMAINS=<cloudfront-domain>
SECURE_COOKIE=true
EOF
```

### Frontend Deployment
Push any change to `Client/` on `feature/full-stack` branch:
```bash
git add Client/
git commit -m "feat: update frontend"
git push origin feature/full-stack
```

### Backend Deployment
Push any change to `Server/` on `feature/full-stack` branch:
```bash
git add Server/
git commit -m "feat: update backend"
git push origin feature/full-stack
```

### Manual Deployment
```bash
# Frontend
chmod +x scripts/deploy-frontend.sh
./scripts/deploy-frontend.sh <s3-bucket> <cloudfront-id>

# Backend health check
chmod +x scripts/health-check.sh
./scripts/health-check.sh <alb-dns-name>
```

---

## 4. Monitoring

### CloudWatch Dashboard
1. Go to AWS Console → CloudWatch → Dashboards
2. Open `starttech-dashboard`
3. Key metrics to watch:
   - ALB Request Count
   - ALB Response Time
   - EC2 CPU Utilization
   - ALB 5XX Errors
   - Healthy vs Unhealthy hosts

### Viewing Logs
```bash
# Latest backend logs
aws logs tail /starttech/backend --follow

# Filter for errors only
aws logs filter-log-events \
  --log-group-name /starttech/backend \
  --filter-pattern "ERROR"

# Last 1 hour of logs
aws logs filter-log-events \
  --log-group-name /starttech/backend \
  --start-time $(date -d '1 hour ago' +%s000)
```

### Log Insights Queries
Go to CloudWatch → Log Insights → select `/starttech/backend`
Use queries from `monitoring/log-insights-queries.txt`

### Alarm Notifications
- All alarms send to SNS topic `starttech-alerts`
- Notifications go to email set in `ALARM_EMAIL` secret
- Confirm the subscription email after first deployment

---

## 5. Scaling

### Manual Scaling
```bash
# Scale up to 3 instances
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name starttech-backend-asg \
  --desired-capacity 3

# Scale down to 1 instance
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name starttech-backend-asg \
  --desired-capacity 1
```

### Auto Scaling Thresholds
| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU > 70% | 2 consecutive periods (4 min) | Add 1 instance |
| CPU < 20% | 2 consecutive periods (4 min) | Remove 1 instance |

### Check ASG Status
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names starttech-backend-asg \
  --query 'AutoScalingGroups[0].{
    Desired:DesiredCapacity,
    Min:MinSize,
    Max:MaxSize,
    Instances:Instances[*].{ID:InstanceId,State:LifecycleState,Health:HealthStatus}
  }'
```

---

## 6. Rollback Procedures

### Frontend Rollback
S3 has versioning enabled. To restore a previous version:
```bash
# List versions
aws s3api list-object-versions \
  --bucket <s3-bucket-name> \
  --prefix index.html

# Restore specific version
aws s3api copy-object \
  --bucket <s3-bucket-name> \
  --copy-source "<bucket>/index.html?versionId=<version-id>" \
  --key index.html

# Invalidate CloudFront
aws cloudfront create-invalidation \
  --distribution-id <cf-distribution-id> \
  --paths "/*"
```

### Backend Rollback
```bash
# Using the rollback script
chmod +x scripts/rollback.sh
ASG_NAME=starttech-backend-asg \
LT_NAME=starttech-backend-lt \
./scripts/rollback.sh
```

Or manually:
```bash
# List launch template versions
aws ec2 describe-launch-template-versions \
  --launch-template-name starttech-backend-lt \
  --query 'LaunchTemplateVersions[*].{Version:VersionNumber,Description:LaunchTemplateData.UserData}' \
  --output table

# Set previous version as default
aws ec2 modify-launch-template \
  --launch-template-name starttech-backend-lt \
  --default-version <previous-version-number>

# Trigger instance refresh
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name starttech-backend-asg \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":60}'
```

---

## 7. Troubleshooting

### Backend instances failing health checks
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# SSH into instance (if you have a key pair)
ssh -i key.pem ec2-user@<instance-ip>

# Check container status
docker ps
docker logs muchtodo --tail 100

# Check if app is listening
curl http://localhost:8080/health
```

### Frontend not updating after deployment
```bash
# Check S3 sync completed
aws s3 ls s3://<bucket-name> --recursive | head -20

# Force CloudFront invalidation
aws cloudfront create-invalidation \
  --distribution-id <cf-id> \
  --paths "/*"

# Check invalidation status
aws cloudfront list-invalidations \
  --distribution-id <cf-id>
```

### Pipeline failing at ECR login
```bash
# Verify ECR repository exists
aws ecr describe-repositories \
  --repository-names starttech-backend

# Test ECR login locally
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

### Redis connection errors
```bash
# Check ElastiCache cluster status
aws elasticache describe-cache-clusters \
  --cache-cluster-id starttech-redis \
  --show-cache-node-info

# Test Redis connectivity from EC2
redis-cli -h <elasticache-endpoint> -p 6379 ping
```

### Terraform state lock
```bash
# If Terraform is stuck with a state lock
terraform force-unlock <lock-id>
```

---

## 8. Disaster Recovery

### Full Infrastructure Rebuild
```bash
cd starttech-infra/terraform
terraform init
terraform apply -auto-approve
```

### Database Recovery
- MongoDB Atlas has automatic daily backups
- Go to Atlas Console → Clusters → Backup → Restore

### Complete Application Recovery Steps
1. Rebuild infrastructure with Terraform
2. Collect new output values
3. Update GitHub Secrets in `much-to-do` repo
4. Update EC2 environment files with new Redis endpoint
5. Re-run backend pipeline to deploy latest image
6. Re-run frontend pipeline to sync S3
7. Verify health via ALB endpoint