#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
REPORT_DIR="$PROJECT_ROOT/reports"
REPORT_FILE="$REPORT_DIR/s3-test-report.md"

ENVIRONMENT="${1:-}"

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 <dev|prod>"
    exit 1
fi

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Invalid environment: $ENVIRONMENT"
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

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS credentials are not configured"
    exit 1
fi

TFVARS="$TERRAFORM_DIR/environments/$ENVIRONMENT.tfvars"

if [[ ! -f "$TFVARS" ]]; then
    echo "Missing file: $TFVARS"
    exit 1
fi

REGION="$(awk -F'"' '/^region[[:space:]]*=/ {print $2}' "$TFVARS")"

if [[ -z "$REGION" ]]; then
    echo "Could not determine AWS region"
    exit 1
fi

PROJECT_NAME="content-translation"

ENGLISH_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-en"
SPANISH_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-es"

PASS_COUNT=0
FAIL_COUNT=0

REPORT_TMP="$(mktemp)"

cleanup() {
    rm -f "$REPORT_TMP"
}

trap cleanup EXIT

write_result() {
    local name="$1"
    local status="$2"

    echo "| $name | $status |" >> "$REPORT_TMP"

    if [[ "$status" == "PASS" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

check_bucket_exists() {
    local bucket="$1"

    aws s3api head-bucket \
        --bucket "$bucket" \
        --region "$REGION" >/dev/null 2>&1
}

check_public_access_block() {
    local bucket="$1"

    local result

    result="$(
        aws s3api get-public-access-block \
            --bucket "$bucket" \
            --region "$REGION" \
            --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]' \
            --output text 2>/dev/null
    )"

    [[ "$result" == $'True\tTrue\tTrue\tTrue' ]]
}

check_ownership() {
    local bucket="$1"

    local result

    result="$(
        aws s3api get-bucket-ownership-controls \
            --bucket "$bucket" \
            --region "$REGION" \
            --output json 2>/dev/null
    )"

    [[ "$result" == *'"ObjectOwnership": "BucketOwnerEnforced"'* ]]
}

check_versioning() {
    local bucket="$1"

    local result

    result="$(
        aws s3api get-bucket-versioning \
            --bucket "$bucket" \
            --region "$REGION" \
            --query 'Status' \
            --output text 2>/dev/null
    )"

    [[ "$result" == "Enabled" ]]
}

check_encryption() {
    local bucket="$1"

    local result

    result="$(
        aws s3api get-bucket-encryption \
            --bucket "$bucket" \
            --region "$REGION" \
            --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
            --output text 2>/dev/null
    )"

    [[ "$result" == "AES256" ]]
}

test_bucket() {
    local language="$1"
    local bucket="$2"

    if check_bucket_exists "$bucket"; then
        write_result "$language content bucket exists" "PASS"
    else
        write_result "$language content bucket exists" "FAIL"
    fi

    if check_public_access_block "$bucket"; then
        write_result "$language bucket public access blocked" "PASS"
    else
        write_result "$language bucket public access blocked" "FAIL"
    fi

    if check_ownership "$bucket"; then
        write_result "$language bucket ownership enforced" "PASS"
    else
        write_result "$language bucket ownership enforced" "FAIL"
    fi

    if check_versioning "$bucket"; then
        write_result "$language bucket versioning enabled" "PASS"
    else
        write_result "$language bucket versioning enabled" "FAIL"
    fi

    if check_encryption "$bucket"; then
        write_result "$language bucket encryption enabled" "PASS"
    else
        write_result "$language bucket encryption enabled" "FAIL"
    fi
}

echo "Running S3 infrastructure tests..."

test_bucket "English" "$ENGLISH_BUCKET"
test_bucket "Spanish" "$SPANISH_BUCKET"

mkdir -p "$REPORT_DIR"

{
    echo "# S3 Infrastructure Test Report"
    echo
    echo "## Environment"
    echo
    echo "- Environment: $ENVIRONMENT"
    echo "- Region: $REGION"
    echo
    echo "## Test Results"
    echo
    echo "| Test | Status |"
    echo "|---|---|"
    cat "$REPORT_TMP"
    echo
    echo "## Summary"
    echo
    echo "- Passed: $PASS_COUNT"
    echo "- Failed: $FAIL_COUNT"
    echo
    if [[ "$FAIL_COUNT" -eq 0 ]]; then
        echo "All S3 infrastructure tests passed."
    else
        echo "One or more S3 infrastructure tests failed."
    fi
} > "$REPORT_FILE"

echo
echo "Test report generated:"
echo "$REPORT_FILE"
echo
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
    exit 1
fi