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
        return
    fi

    while true; do
        local objects
        objects="$(aws s3api list-object-versions \
            --bucket "$bucket" \
            --region "$BACKEND_REGION" \
            --output json)"

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
}

destroy_environment() {
    local environment="$1"
    local backend_env="$TERRAFORM_DIR/backend/$environment.hcl"

    if [[ ! -f "$backend_env" ]]; then
        echo "Missing configuration for environment: $environment"
        exit 1
    fi

    echo
    echo "Cleaning environment: $environment"

    cd "$TERRAFORM_DIR"

    terraform init \
        -reconfigure \
        -backend-config="$BACKEND_SHARED" \
        -backend-config="$backend_env"

    terraform destroy
}

echo
if [[ "$TARGET" == "all" ]]; then
    echo "This will destroy dev and prod resources."
    echo "The shared Terraform backend will also be deleted."
else
    echo "This will destroy all $TARGET resources."
    echo "The shared Terraform backend will be kept."
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

    echo
    echo "Emptying shared Terraform backend..."

    empty_bucket "$BACKEND_BUCKET"

    echo
    echo "Deleting shared Terraform backend..."

    aws s3api delete-bucket \
        --bucket "$BACKEND_BUCKET" \
        --region "$BACKEND_REGION"

    echo "Shared Terraform backend deleted."
else
    destroy_environment "$TARGET"
fi

echo
echo "Cleanup completed."