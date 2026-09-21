#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <dev|prod|all>"
    exit 1
fi

if [[ "$TARGET" != "dev" && "$TARGET" != "prod" && "$TARGET" != "all" ]]; then
    echo "Invalid target: $TARGET"
    exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI is not installed"
    exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
    echo "Terraform is not installed"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is not installed"
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS credentials are not configured"
    exit 1
fi

BACKEND_SHARED="$TERRAFORM_DIR/backend/backend.hcl"

if [[ ! -f "$BACKEND_SHARED" ]]; then
    echo "Missing file: $BACKEND_SHARED"
    exit 1
fi

BACKEND_BUCKET="$(awk -F'"' '/^bucket[[:space:]]*=/ {print $2}' "$BACKEND_SHARED")"
BACKEND_REGION="$(awk -F'"' '/^region[[:space:]]*=/ {print $2}' "$BACKEND_SHARED")"

if [[ -z "$BACKEND_BUCKET" || -z "$BACKEND_REGION" ]]; then
    echo "Invalid shared backend configuration"
    exit 1
fi

empty_bucket() {
    local bucket="$1"

    if ! aws s3api head-bucket \
        --bucket "$bucket" \
        --region "$BACKEND_REGION" >/dev/null 2>&1; then
        echo "Bucket does not exist: $bucket"
        return 0
    fi

    echo "Emptying bucket: $bucket"

    while true; do
        local objects
        objects="$(
            aws s3api list-object-versions \
                --bucket "$bucket" \
                --region "$BACKEND_REGION" \
                --output json
        )"

        local count
        count="$(jq '[.Versions[]?, .DeleteMarkers[]?] | length' <<< "$objects")"

        if [[ "$count" -eq 0 ]]; then
            break
        fi

        jq '{
            Objects: (
                [
                    .Versions[]? |
                    {
                        Key: .Key,
                        VersionId: .VersionId
                    }
                ] + [
                    .DeleteMarkers[]? |
                    {
                        Key: .Key,
                        VersionId: .VersionId
                    }
                ]
            ),
            Quiet: true
        }' <<< "$objects" > /tmp/s3-delete-objects.json

        aws s3api delete-objects \
            --bucket "$bucket" \
            --region "$BACKEND_REGION" \
            --delete file:///tmp/s3-delete-objects.json >/dev/null
    done

    echo "Bucket is empty: $bucket"
}

is_backend_empty() {
    if ! aws s3api head-bucket \
        --bucket "$BACKEND_BUCKET" \
        --region "$BACKEND_REGION" >/dev/null 2>&1; then
        return 0
    fi

    local objects
    objects="$(
        aws s3api list-object-versions \
            --bucket "$BACKEND_BUCKET" \
            --region "$BACKEND_REGION" \
            --output json
    )"

    local count
    count="$(jq '[.Versions[]?, .DeleteMarkers[]?] | length' <<< "$objects")"

    [[ "$count" -eq 0 ]]
}

delete_backend() {
    if ! aws s3api head-bucket \
        --bucket "$BACKEND_BUCKET" \
        --region "$BACKEND_REGION" >/dev/null 2>&1; then
        echo "Shared Terraform backend does not exist."
        return 0
    fi

    echo
    echo "Emptying shared Terraform backend..."

    empty_bucket "$BACKEND_BUCKET"

    if ! is_backend_empty; then
        echo "Shared Terraform backend is not empty."
        echo "Backend bucket will not be deleted."
        exit 1
    fi

    echo
    echo "Deleting shared Terraform backend..."

    aws s3api delete-bucket \
        --bucket "$BACKEND_BUCKET" \
        --region "$BACKEND_REGION"

    echo "Shared Terraform backend deleted."
}

environment_has_resources() {
    local environment="$1"
    local backend_env="$TERRAFORM_DIR/backend/$environment.hcl"
    local tfvars="$TERRAFORM_DIR/environments/$environment.tfvars"

    if [[ ! -f "$backend_env" || ! -f "$tfvars" ]]; then
        return 1
    fi

    cd "$TERRAFORM_DIR"

    terraform init \
        -reconfigure \
        -backend-config="$BACKEND_SHARED" \
        -backend-config="$backend_env" >/dev/null

    local state
    state="$(terraform state list 2>/dev/null || true)"

    [[ -n "$state" ]]
}

destroy_environment() {
    local environment="$1"
    local backend_env="$TERRAFORM_DIR/backend/$environment.hcl"
    local tfvars="$TERRAFORM_DIR/environments/$environment.tfvars"

    if [[ ! -f "$backend_env" ]]; then
        echo "Missing backend configuration for environment: $environment"
        exit 1
    fi

    if [[ ! -f "$tfvars" ]]; then
        echo "Missing variables file for environment: $environment"
        exit 1
    fi

    echo
    echo "Cleaning environment: $environment"

    cd "$TERRAFORM_DIR"

    terraform init \
        -reconfigure \
        -backend-config="$BACKEND_SHARED" \
        -backend-config="$backend_env"

    terraform destroy \
        -var-file="$tfvars"
}

cleanup_single_environment() {
    local environment="$1"
    local other_environment

    if [[ "$environment" == "dev" ]]; then
        other_environment="prod"
    else
        other_environment="dev"
    fi

    destroy_environment "$environment"

    echo
    echo "Checking remaining environment: $other_environment"

    if environment_has_resources "$other_environment"; then
        echo "Environment '$other_environment' still has Terraform resources."
        echo "Shared Terraform backend will be kept."
    else
        echo "Environment '$other_environment' has no Terraform resources."
        echo "No environment requires the shared Terraform backend."

        delete_backend
    fi
}

echo

if [[ "$TARGET" == "all" ]]; then
    echo "This will destroy dev and prod resources."
    echo "The shared Terraform backend will also be deleted."
else
    echo "This will destroy all $TARGET resources."

    if [[ "$TARGET" == "dev" ]]; then
        echo "After cleanup, prod will be checked."
    else
        echo "After cleanup, dev will be checked."
    fi

    echo "The shared Terraform backend will be deleted only if no other environment has resources."
fi

echo

read -r -p "Continue? [y/N] " confirmation

case "$confirmation" in
    y|Y|yes|YES|Yes)
        echo "Cleanup confirmed."
        ;;
    *)
        echo "Cleanup cancelled."
        exit 0
        ;;
esac

if [[ "$TARGET" == "all" ]]; then
    destroy_environment "dev"
    destroy_environment "prod"
    delete_backend
else
    cleanup_single_environment "$TARGET"
fi

echo
echo "Cleanup completed."