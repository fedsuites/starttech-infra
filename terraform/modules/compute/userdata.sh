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

# Write env file
mkdir -p /etc/muchtodo
cat > /etc/muchtodo/env << ENVEOF
PORT=8080
MONGO_URI=${mongo_uri}
DB_NAME=much_todo_db
JWT_SECRET_KEY=${jwt_secret}
JWT_EXPIRATION_HOURS=72
ENABLE_CACHE=false
LOG_LEVEL=INFO
LOG_FORMAT=json
ALLOWED_ORIGINS=*
SECURE_COOKIE=false
ENVEOF

echo "=== ENV FILE CONTENTS ==="
cat /etc/muchtodo/env
echo "=== END ENV FILE ==="

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  445567073243.dkr.ecr.$AWS_REGION.amazonaws.com

# Pull and run container
docker pull 445567073243.dkr.ecr.$AWS_REGION.amazonaws.com/${ecr_repository_name}:latest

docker stop muchtodo 2>/dev/null || true
docker rm muchtodo 2>/dev/null || true

docker run -d \
  --name muchtodo \
  --restart unless-stopped \
  -p 8080:8080 \
  --env-file /etc/muchtodo/env \
  445567073243.dkr.ecr.$AWS_REGION.amazonaws.com/${ecr_repository_name}:latest

# Wait for container to start or fail
sleep 10

# Capture container logs
docker logs muchtodo > /var/log/muchtodo-startup.log 2>&1 || true
docker inspect muchtodo >> /var/log/muchtodo-startup.log 2>&1 || true

echo "=== CONTAINER STARTUP LOG ==="
cat /var/log/muchtodo-startup.log
echo "=== END CONTAINER LOG ==="
echo "Backend container started successfully"