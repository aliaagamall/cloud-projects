#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="personal-website"
AWS_REGION="us-east-1"
STATE_BUCKET="aliaa-personal-website-tfstate"
STATE_KEY="projects/personal-website/terraform.tfstate"

TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"

echo "Checking required tools..."

command -v terraform >/dev/null 2>&1 || {
  echo "Error: Terraform is not installed."
  exit 1
}

command -v aws >/dev/null 2>&1 || {
  echo "Error: AWS CLI is not installed."
  exit 1
}

echo "Terraform: $(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)"
echo "AWS CLI: $(aws --version)"

echo
echo "Checking AWS authentication..."

aws sts get-caller-identity >/dev/null

echo "AWS authentication is valid."

echo
echo "Checking Terraform state bucket..."

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  echo "State bucket already exists: $STATE_BUCKET"
else
  echo "Creating state bucket: $STATE_BUCKET"

  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$AWS_REGION"
  else
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"
  fi
fi

echo
echo "Configuring state bucket security..."

aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration \
  '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

echo
echo "Initializing Terraform..."

cd "$TERRAFORM_DIR"

terraform init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY" \
  -backend-config="region=$AWS_REGION"

echo
echo "Formatting Terraform..."

terraform fmt -recursive

echo
echo "Validating Terraform configuration..."

terraform validate

echo
echo "Terraform setup completed successfully."