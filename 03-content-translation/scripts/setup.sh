#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

ENVIRONMENT="${1:-}"

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <dev|prod>"
    exit 1
fi

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Invalid environment: $ENVIRONMENT"
    exit 1
fi

BACKEND_SHARED="$TERRAFORM_DIR/backend/backend.hcl"
BACKEND_ENV="$TERRAFORM_DIR/backend/$ENVIRONMENT.hcl"
TFVARS="$TERRAFORM_DIR/environments/$ENVIRONMENT.tfvars"

for file in "$BACKEND_SHARED" "$BACKEND_ENV" "$TFVARS"; do
    if [[ ! -f "$file" ]]; then
        echo "Missing file: $file"
        exit 1
    fi
done

if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI is not installed"
    exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
    echo "Terraform is not installed"
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS credentials are not configured"
    exit 1
fi

BACKEND_BUCKET="$(awk -F'"' '/^bucket[[:space:]]*=/ {print $2}' "$BACKEND_SHARED")"
BACKEND_REGION="$(awk -F'"' '/^region[[:space:]]*=/ {print $2}' "$BACKEND_SHARED")"

if [[ -z "$BACKEND_BUCKET" || -z "$BACKEND_REGION" ]]; then
    echo "Invalid shared backend configuration"
    exit 1
fi

if ! aws s3api head-bucket \
    --bucket "$BACKEND_BUCKET" \
    --region "$BACKEND_REGION" >/dev/null 2>&1; then

    echo "Creating backend bucket: $BACKEND_BUCKET"

    if [[ "$BACKEND_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket "$BACKEND_BUCKET" \
            --region "$BACKEND_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BACKEND_BUCKET" \
            --region "$BACKEND_REGION" \
            --create-bucket-configuration \
            "LocationConstraint=$BACKEND_REGION"
    fi

    aws s3api put-bucket-versioning \
        --bucket "$BACKEND_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$BACKEND_REGION"

    aws s3api put-bucket-encryption \
        --bucket "$BACKEND_BUCKET" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
        --region "$BACKEND_REGION"
fi

cd "$TERRAFORM_DIR"

terraform init \
    -reconfigure \
    -backend-config="$BACKEND_SHARED" \
    -backend-config="$BACKEND_ENV"

echo
echo "Terraform backend ready."
echo "Environment: $ENVIRONMENT"
echo "Backend:     $BACKEND_BUCKET"
echo "Region:      $BACKEND_REGION"
echo "Variables:   $TFVARS"