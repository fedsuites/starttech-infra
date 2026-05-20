#!/bin/bash
set -euo pipefail

# Deploy infrastructure using Terraform
# Usage: ./deploy-infrastructure.sh [plan|apply|destroy]

ACTION=${1:-plan}
TERRAFORM_DIR="$(dirname "$0")/../terraform"
STATE_BUCKET="starttech-terraform-state-829350946407"
AWS_REGION=${AWS_REGION:-"us-east-1"}

echo "Starting infrastructure deployment — action: $ACTION"

# Check required tools
for tool in terraform aws; do
  if ! command -v $tool &> /dev/null; then
    echo " Required tool not found: $tool"
    exit 1
  fi
done

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
  echo " AWS credentials not configured"
  exit 1
fi

echo " AWS credentials verified"

# Create S3 state bucket if it doesn't exist
if ! aws s3 ls "s3://$STATE_BUCKET" 2>/dev/null; then
  echo " Creating Terraform state bucket: $STATE_BUCKET"
  aws s3 mb "s3://$STATE_BUCKET" --region "$AWS_REGION"
  aws s3api put-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption \
    --bucket "$STATE_BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'
  echo "State bucket created"
fi

cd "$TERRAFORM_DIR"

# Initialize Terraform
echo "  Initializing Terraform..."
terraform init -reconfigure

# Validate configuration
echo " Validating Terraform configuration..."
terraform validate

case "$ACTION" in
  plan)
    echo " Running Terraform plan..."
    terraform plan -out=tfplan
    ;;
  apply)
    echo "  Applying Terraform configuration..."
    if [ -f tfplan ]; then
      terraform apply tfplan
    else
      terraform apply -auto-approve
    fi
    echo "Infrastructure deployed successfully"
    echo ""
    echo "Outputs:"
    terraform output
    ;;
  destroy)
    echo " Destroying infrastructure..."
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    if [ "$confirm" = "yes" ]; then
      terraform destroy -auto-approve
      echo " Infrastructure destroyed"
    else
      echo " Destroy cancelled"
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [plan|apply|destroy]"
    exit 1
    ;;
esac