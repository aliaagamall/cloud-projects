#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
PLANS_DIR="$PROJECT_ROOT/plans"

ENVIRONMENT="${1:-}"
PLAN_FILE="${2:-}"

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <dev|prod> [plan-file]"
    exit 1
fi

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Invalid environment: $ENVIRONMENT"
    exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
    echo "Terraform is not installed"
    exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI is not installed"
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS credentials are not configured"
    exit 1
fi

BACKEND_SHARED="$TERRAFORM_DIR/backend/backend.hcl"
BACKEND_ENV="$TERRAFORM_DIR/backend/$ENVIRONMENT.hcl"
TFVARS="$TERRAFORM_DIR/environments/$ENVIRONMENT.tfvars"

if [[ ! -f "$BACKEND_SHARED" ]]; then
    echo "Missing file: $BACKEND_SHARED"
    exit 1
fi

if [[ ! -f "$BACKEND_ENV" ]]; then
    echo "Missing file: $BACKEND_ENV"
    exit 1
fi

if [[ ! -f "$TFVARS" ]]; then
    echo "Missing file: $TFVARS"
    exit 1
fi

if [[ -z "$PLAN_FILE" ]]; then
    PLAN_FILE="$PLANS_DIR/$ENVIRONMENT.tfplan"
elif [[ "$PLAN_FILE" != /* ]]; then
    PLAN_FILE="$PROJECT_ROOT/$PLAN_FILE"
fi

mkdir -p "$(dirname "$PLAN_FILE")"

cd "$TERRAFORM_DIR"

echo
echo "=== Terraform Init ==="

terraform init \
    -upgrade \
    -reconfigure \
    -backend-config="$BACKEND_SHARED" \
    -backend-config="$BACKEND_ENV"

echo
echo "=== Terraform Format ==="

terraform fmt -recursive

echo
echo "=== Terraform Validate ==="

terraform validate

echo
echo "Environment: $ENVIRONMENT"
echo "Variables:   $TFVARS"
echo "Plan file:   $PLAN_FILE"

if [[ -f "$PLAN_FILE" ]]; then
    echo
    echo "Existing plan found."
    echo "A saved plan is a snapshot and may be outdated."
    echo

    read -r -p "Use this plan? [y/N] " confirmation

    case "$confirmation" in
        y|Y|yes|YES|Yes)
            echo "Using existing plan."
            ;;
        *)
            echo
            echo "Discarding existing plan..."
            rm -f "$PLAN_FILE"

            echo
            echo "=== Terraform Plan ==="

            terraform plan \
                -var-file="$TFVARS" \
                -out="$PLAN_FILE"
            ;;
    esac
else
    echo
    echo "=== Terraform Plan ==="

    terraform plan \
        -var-file="$TFVARS" \
        -out="$PLAN_FILE"
fi

echo
echo "=== Saved Plan ==="

terraform show "$PLAN_FILE"

echo
echo "The plan above will be applied to: $ENVIRONMENT"
echo "Plan file: $PLAN_FILE"
echo

read -r -p "Apply this plan? [y/N] " confirmation

case "$confirmation" in
    y|Y|yes|YES|Yes)
        echo
        echo "=== Terraform Apply ==="

        terraform apply "$PLAN_FILE"
        ;;
    *)
        echo
        echo "Apply cancelled."
        exit 0
        ;;
esac

echo
echo "Deployment completed."
