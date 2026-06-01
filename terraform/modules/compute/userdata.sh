#!/bin/bash
set -e

# Install Docker and AWS CLI
yum update -y
yum install -y docker aws-cli amazon-cloudwatch-agent
systemctl start docker
systemctl enable docker

# Get instance metadata
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Create env file
mkdir -p /etc/muchtodo
cat > /etc/muchtodo/env << 'ENVFILE'
PORT=8080
MONGO_URI=${mongo_uri}
DB_NAME=much_todo_db
JWT_SECRET_KEY=${jwt_secret}
JWT_EXPIRATION_HOURS=72
ENABLE_CACHE=true
REDIS_ADDR=${redis_addr}
LOG_LEVEL=INFO
LOG_FORMAT=json
ALLOWED_ORIGINS=*
SECURE_COOKIE=false
ENVFILE

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/muchtodo/app.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWCONFIG

systemctl start amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  445567073243.dkr.ecr.$AWS_REGION.amazonaws.com

# Pull and run container
docker pull 445567073243.dkr.ecr.$AWS_REGION.amazonaws.com/${ecr_repository_name}:latest

docker stop muchtodo 2>/dev/null || true
docker rm muchtodo 2>/dev/null || true

mkdir -p /var/log/muchtodo

docker run -d \
  --name muchtodo \
  --restart unless-stopped \
  -p 8080:8080 \
  -e PORT=8080 \
  -e MONGO_URI="${mongo_uri}" \
  -e DB_NAME=much_todo_db \
  -e JWT_SECRET_KEY="${jwt_secret}" \
  -e JWT_EXPIRATION_HOURS=72 \
  -e ENABLE_CACHE=false \
  -e REDIS_ADDR="${redis_addr}" \
  -e LOG_LEVEL=INFO \
  -e LOG_FORMAT=json \
  -e ALLOWED_ORIGINS="*" \
  -e SECURE_COOKIE=false \
  445567073243.dkr.ecr.$AWS_REGION.amazonaws.com/${ecr_repository_name}:latest

echo "Backend container started successfully"