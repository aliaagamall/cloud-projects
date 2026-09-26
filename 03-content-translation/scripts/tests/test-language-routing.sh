#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
REPORT_FILE="$PROJECT_DIR/reports/language-routing-test-report.md"

mkdir -p "$PROJECT_DIR/reports"

cd "$TERRAFORM_DIR"

DISTRIBUTION_DOMAIN="$(
  terraform output -raw cloudfront_domain_name
)"

DISTRIBUTION_ID="$(
  terraform output -raw cloudfront_distribution_id
)"

EN_BUCKET="$(
  terraform output -json content_bucket_names |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["en"])'
)"

ES_BUCKET="$(
  terraform output -json content_bucket_names |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["es"])'
)"

if [[ -z "$DISTRIBUTION_DOMAIN" ]]; then
  echo "ERROR: CloudFront domain name is empty."
  exit 1
fi

if [[ -z "$DISTRIBUTION_ID" ]]; then
  echo "ERROR: CloudFront distribution ID is empty."
  exit 1
fi

if [[ -z "$EN_BUCKET" || -z "$ES_BUCKET" ]]; then
  echo "ERROR: Could not determine language buckets."
  exit 1
fi

TEST_KEY="__language-routing-test-$(date +%s).txt"

EN_CONTENT="language-routing-test-en"
ES_CONTENT="language-routing-test-es"

REPORT_TMP="$(mktemp)"

PASSED=0
FAILED=0

CLOUDFRONT_DEPLOYED="FAIL"
LAMBDA_ASSOCIATED="FAIL"
CLOUDFRONT_USES_OAI="FAIL"
CLOUDFRONT_USES_NO_OAC="FAIL"
S3_EN_PUBLIC_BLOCKED="FAIL"
S3_ES_PUBLIC_BLOCKED="FAIL"
EN_ROUTING="FAIL"
ES_ROUTING="FAIL"
DEFAULT_ROUTING="FAIL"

cleanup() {
  rm -f "$REPORT_TMP"

  for bucket in "$EN_BUCKET" "$ES_BUCKET"; do
    versions="$(
      aws s3api list-object-versions \
        --bucket "$bucket" \
        --prefix "$TEST_KEY" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null || true
    )"

    if [[ -n "$versions" ]]; then
      while read -r key version_id; do
        [[ -z "$key" || -z "$version_id" ]] && continue

        aws s3api delete-object \
          --bucket "$bucket" \
          --key "$key" \
          --version-id "$version_id" \
          >/dev/null 2>&1 || true
      done <<< "$versions"
    fi

    delete_markers="$(
      aws s3api list-object-versions \
        --bucket "$bucket" \
        --prefix "$TEST_KEY" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null || true
    )"

    if [[ -n "$delete_markers" ]]; then
      while read -r key version_id; do
        [[ -z "$key" || -z "$version_id" ]] && continue

        aws s3api delete-object \
          --bucket "$bucket" \
          --key "$key" \
          --version-id "$version_id" \
          >/dev/null 2>&1 || true
      done <<< "$delete_markers"
    fi
  done
}

trap cleanup EXIT

run_test() {
  local name="$1"
  local command="$2"

  if eval "$command"; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
    return 0
  else
    echo "FAIL: $name"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

cat > "$REPORT_TMP" <<EOF
# Lambda@Edge Language Routing Test Report

## Test Information

- Distribution: CloudFront
- Test object: temporary
- Languages: English and Spanish

EOF

echo "Running Lambda@Edge language routing tests..."
echo

echo "Checking CloudFront deployment status..."

STATUS="$(
  aws cloudfront get-distribution \
    --id "$DISTRIBUTION_ID" \
    --query 'Distribution.Status' \
    --output text
)"

if run_test \
  "CloudFront distribution is deployed" \
  "[[ \"$STATUS\" == \"Deployed\" ]]"; then
  CLOUDFRONT_DEPLOYED="PASS"
fi

echo "Checking CloudFront Lambda@Edge association..."

LAMBDA_ARN="$(
  aws cloudfront get-distribution-config \
    --id "$DISTRIBUTION_ID" \
    --query 'DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations.Items[?EventType==`origin-request`].LambdaFunctionARN' \
    --output text
)"

if run_test \
  "Lambda@Edge is associated with origin-request" \
  "[[ -n \"$LAMBDA_ARN\" && \"$LAMBDA_ARN\" != \"None\" ]]"; then
  LAMBDA_ASSOCIATED="PASS"
fi

echo "Checking CloudFront origins..."

ORIGIN_ACCESS_CONTROL="$(
  aws cloudfront get-distribution-config \
    --id "$DISTRIBUTION_ID" \
    --query 'DistributionConfig.Origins.Items[].OriginAccessControlId' \
    --output text
)"

ORIGIN_ACCESS_IDENTITY="$(
  aws cloudfront get-distribution-config \
    --id "$DISTRIBUTION_ID" \
    --query 'DistributionConfig.Origins.Items[].S3OriginConfig.OriginAccessIdentity' \
    --output text
)"

OAI_FOUND="false"

while read -r value; do
  if [[ -n "$value" && "$value" != "None" ]]; then
    OAI_FOUND="true"
    break
  fi
done <<< "$(printf '%s\n' "$ORIGIN_ACCESS_IDENTITY" | tr '\t' '\n' | tr ' ' '\n')"

if run_test \
  "CloudFront uses Origin Access Identity" \
  "[[ \"$OAI_FOUND\" == \"true\" ]]"; then
  CLOUDFRONT_USES_OAI="PASS"
fi

OAC_FOUND="false"

while read -r value; do
  if [[ -n "$value" && "$value" != "None" ]]; then
    OAC_FOUND="true"
    break
  fi
done <<< "$(printf '%s\n' "$ORIGIN_ACCESS_CONTROL" | tr '\t' '\n' | tr ' ' '\n')"

if run_test \
  "CloudFront does not use Origin Access Control" \
  "[[ \"$OAC_FOUND\" == \"false\" ]]"; then
  CLOUDFRONT_USES_NO_OAC="PASS"
fi

echo "Checking S3 public access..."

check_public_access_block() {
  local bucket="$1"

  local block_public_acls
  local block_public_policy
  local ignore_public_acls
  local restrict_public_buckets

  block_public_acls="$(
    aws s3api get-public-access-block \
      --bucket "$bucket" \
      --query 'PublicAccessBlockConfiguration.BlockPublicAcls' \
      --output text
  )"

  block_public_policy="$(
    aws s3api get-public-access-block \
      --bucket "$bucket" \
      --query 'PublicAccessBlockConfiguration.BlockPublicPolicy' \
      --output text
  )"

  ignore_public_acls="$(
    aws s3api get-public-access-block \
      --bucket "$bucket" \
      --query 'PublicAccessBlockConfiguration.IgnorePublicAcls' \
      --output text
  )"

  restrict_public_buckets="$(
    aws s3api get-public-access-block \
      --bucket "$bucket" \
      --query 'PublicAccessBlockConfiguration.RestrictPublicBuckets' \
      --output text
  )"

  [[ "$block_public_acls" == "True" ]] &&
  [[ "$block_public_policy" == "True" ]] &&
  [[ "$ignore_public_acls" == "True" ]] &&
  [[ "$restrict_public_buckets" == "True" ]]
}

if run_test \
  "Public access blocked for $EN_BUCKET" \
  "check_public_access_block \"$EN_BUCKET\""; then
  S3_EN_PUBLIC_BLOCKED="PASS"
fi

if run_test \
  "Public access blocked for $ES_BUCKET" \
  "check_public_access_block \"$ES_BUCKET\""; then
  S3_ES_PUBLIC_BLOCKED="PASS"
fi

echo "Uploading temporary language markers..."

printf '%s\n' "$EN_CONTENT" | \
  aws s3 cp - "s3://$EN_BUCKET/$TEST_KEY" \
  --content-type text/plain \
  >/dev/null

printf '%s\n' "$ES_CONTENT" | \
  aws s3 cp - "s3://$ES_BUCKET/$TEST_KEY" \
  --content-type text/plain \
  >/dev/null

echo "Waiting briefly for S3 objects to become available..."

sleep 3

echo "Testing English routing..."

EN_RESPONSE="$(
  curl -fsS \
    -H "Accept-Language: en" \
    "https://$DISTRIBUTION_DOMAIN/$TEST_KEY"
)"

if run_test \
  "Accept-Language: en routes to English content" \
  "[[ \"$EN_RESPONSE\" == \"$EN_CONTENT\" ]]"; then
  EN_ROUTING="PASS"
fi

echo "Testing Spanish routing..."

ES_RESPONSE="$(
  curl -fsS \
    -H "Accept-Language: es" \
    "https://$DISTRIBUTION_DOMAIN/$TEST_KEY"
)"

if run_test \
  "Accept-Language: es routes to Spanish content" \
  "[[ \"$ES_RESPONSE\" == \"$ES_CONTENT\" ]]"; then
  ES_ROUTING="PASS"
fi

echo "Testing default language..."

DEFAULT_RESPONSE="$(
  curl -fsS \
    -H "Accept-Language: fr" \
    "https://$DISTRIBUTION_DOMAIN/$TEST_KEY"
)"

if run_test \
  "Unsupported language falls back to English" \
  "[[ \"$DEFAULT_RESPONSE\" == \"$EN_CONTENT\" ]]"; then
  DEFAULT_ROUTING="PASS"
fi

cat >> "$REPORT_TMP" <<EOF
## Results

| Test | Result |
|---|---|
| CloudFront deployed | $CLOUDFRONT_DEPLOYED |
| Lambda@Edge origin-request association | $LAMBDA_ASSOCIATED |
| CloudFront uses OAI | $CLOUDFRONT_USES_OAI |
| CloudFront does not use OAC | $CLOUDFRONT_USES_NO_OAC |
| English S3 public access blocked | $S3_EN_PUBLIC_BLOCKED |
| Spanish S3 public access blocked | $S3_ES_PUBLIC_BLOCKED |
| English routing | $EN_ROUTING |
| Spanish routing | $ES_ROUTING |
| Unsupported language fallback | $DEFAULT_ROUTING |

## Summary

- Passed: $PASSED
- Failed: $FAILED

EOF

mv "$REPORT_TMP" "$REPORT_FILE"

echo
echo "Test report generated:"
echo "$REPORT_FILE"
echo
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
