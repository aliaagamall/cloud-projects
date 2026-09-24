#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
REPORT_FILE="$PROJECT_ROOT/reports/cloudfront-test-report.md"

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

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is not installed"
    exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS credentials are not configured"
    exit 1
fi

TFVARS="$TERRAFORM_DIR/environments/$ENVIRONMENT.tfvars"

if [[ ! -f "$TFVARS" ]]; then
    echo "Missing variables file: $TFVARS"
    exit 1
fi

cd "$TERRAFORM_DIR"

DISTRIBUTION_ID="$(terraform output -raw cloudfront_distribution_id)"

REGION="$(
    awk -F'"' '/^region[[:space:]]*=/ {print $2}' "$TFVARS"
)"

PASSED=0
FAILED=0

declare -a RESULTS

record_pass() {
    local test_name="$1"

    RESULTS+=("| $test_name | PASS |")
    PASSED=$((PASSED + 1))
}

record_fail() {
    local test_name="$1"

    RESULTS+=("| $test_name | FAIL |")
    FAILED=$((FAILED + 1))
}

echo "Running CloudFront infrastructure tests..."

DISTRIBUTION_CONFIG="$(
    aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --output json
)"

DISTRIBUTION="$(
    aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --output json
)"

STATUS="$(
    jq -r '.Distribution.Status' <<< "$DISTRIBUTION"
)"

ENABLED="$(
    jq -r '.DistributionConfig.Enabled' <<< "$DISTRIBUTION_CONFIG"
)"

DEFAULT_ROOT_OBJECT="$(
    jq -r '.DistributionConfig.DefaultRootObject' <<< "$DISTRIBUTION_CONFIG"
)"

MINIMUM_PROTOCOL_VERSION="$(
    jq -r '.DistributionConfig.ViewerCertificate.MinimumProtocolVersion' \
        <<< "$DISTRIBUTION_CONFIG"
)"

VIEWER_PROTOCOL_POLICY="$(
    jq -r '.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy' \
        <<< "$DISTRIBUTION_CONFIG"
)"

ORIGIN_COUNT="$(
    jq '.DistributionConfig.Origins.Items | length' \
        <<< "$DISTRIBUTION_CONFIG"
)"

OAC_COUNT="$(
    jq '[.DistributionConfig.Origins.Items[]
        | select(.OriginAccessControlId != null and .OriginAccessControlId != "")]
        | length' \
        <<< "$DISTRIBUTION_CONFIG"
)"

if [[ "$STATUS" == "Deployed" ]]; then
    record_pass "CloudFront distribution deployed"
else
    record_fail "CloudFront distribution deployed"
fi

if [[ "$ENABLED" == "true" ]]; then
    record_pass "CloudFront distribution enabled"
else
    record_fail "CloudFront distribution enabled"
fi

if [[ "$DEFAULT_ROOT_OBJECT" == "index.html" ]]; then
    record_pass "Default root object configured"
else
    record_fail "Default root object configured"
fi

if [[ "$MINIMUM_PROTOCOL_VERSION" == "TLSv1" ]]; then
    record_pass "Minimum TLS version configured"
else
    record_fail "Minimum TLS version configured"
fi

if [[ "$VIEWER_PROTOCOL_POLICY" == "redirect-to-https" ]]; then
    record_pass "HTTP requests redirect to HTTPS"
else
    record_fail "HTTP requests redirect to HTTPS"
fi

if [[ "$ORIGIN_COUNT" -eq 2 ]]; then
    record_pass "Language origins configured"
else
    record_fail "Language origins configured"
fi

if [[ "$OAC_COUNT" -eq "$ORIGIN_COUNT" ]]; then
    record_pass "All S3 origins use CloudFront OAC"
else
    record_fail "All S3 origins use CloudFront OAC"
fi

mkdir -p "$(dirname "$REPORT_FILE")"

{
    echo "# CloudFront Infrastructure Test Report"
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

    printf '%s\n' "${RESULTS[@]}"

    echo
    echo "## Summary"
    echo
    echo "- Passed: $PASSED"
    echo "- Failed: $FAILED"
    echo

    if [[ "$FAILED" -eq 0 ]]; then
        echo "All CloudFront infrastructure tests passed."
    else
        echo "Some CloudFront infrastructure tests failed."
    fi
} > "$REPORT_FILE"

echo
echo "Test report generated:"
echo "$REPORT_FILE"
echo
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi