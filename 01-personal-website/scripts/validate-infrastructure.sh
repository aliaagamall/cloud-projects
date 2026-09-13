#!/usr/bin/env bash

set -euo pipefail

PROJECT_NAME="personal-website"
AWS_REGION="us-east-1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "[PASS] $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "[FAIL] $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: $1 is not installed."
    exit 1
  }
}

echo "========================================"
echo "Personal Website Infrastructure Validation"
echo "========================================"
echo

check_command terraform
check_command aws

cd "$TERRAFORM_DIR"

echo "Checking AWS authentication..."
if aws sts get-caller-identity >/dev/null 2>&1; then
  pass "AWS authentication"
else
  fail "AWS authentication"
fi

echo
echo "Checking Terraform configuration..."

if terraform fmt -check -recursive >/dev/null 2>&1; then
  pass "Terraform formatting"
else
  fail "Terraform formatting"
fi

if terraform validate >/dev/null 2>&1; then
  pass "Terraform validation"
else
  fail "Terraform validation"
fi

echo
echo "Reading Terraform outputs..."

BUCKET_NAME="$(terraform output -raw website_bucket_name)"
BUCKET_ARN="$(terraform output -raw website_bucket_arn)"
DISTRIBUTION_ID="$(terraform output -raw cloudfront_distribution_id)"
CLOUDFRONT_DOMAIN="$(terraform output -raw cloudfront_domain_name)"

if [ -n "$BUCKET_NAME" ]; then
  pass "Website bucket output"
else
  fail "Website bucket output"
fi

if [ -n "$DISTRIBUTION_ID" ]; then
  pass "CloudFront distribution output"
else
  fail "CloudFront distribution output"
fi

if [ -n "$CLOUDFRONT_DOMAIN" ]; then
  pass "CloudFront domain output"
else
  fail "CloudFront domain output"
fi

echo
echo "Checking S3..."

if aws s3api head-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  pass "S3 bucket exists"
else
  fail "S3 bucket exists"
fi

PUBLIC_ACCESS_BLOCK="$(aws s3api get-public-access-block \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --query 'PublicAccessBlockConfiguration' \
  --output json)"

if echo "$PUBLIC_ACCESS_BLOCK" | grep -q '"BlockPublicAcls": true' &&
   echo "$PUBLIC_ACCESS_BLOCK" | grep -q '"IgnorePublicAcls": true' &&
   echo "$PUBLIC_ACCESS_BLOCK" | grep -q '"BlockPublicPolicy": true' &&
   echo "$PUBLIC_ACCESS_BLOCK" | grep -q '"RestrictPublicBuckets": true'; then
  pass "S3 public access block"
else
  fail "S3 public access block"
fi

OWNERSHIP="$(aws s3api get-bucket-ownership-controls \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --query 'OwnershipControls.Rules[0].ObjectOwnership' \
  --output text)"

if [ "$OWNERSHIP" = "BucketOwnerEnforced" ]; then
  pass "S3 ownership controls"
else
  fail "S3 ownership controls"
fi

VERSIONING="$(aws s3api get-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --query 'Status' \
  --output text)"

if [ "$VERSIONING" = "Enabled" ]; then
  pass "S3 versioning"
else
  fail "S3 versioning"
fi

ENCRYPTION="$(aws s3api get-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
  --output text 2>/dev/null || true)"

if [ "$ENCRYPTION" = "AES256" ]; then
  pass "S3 server-side encryption"
else
  fail "S3 server-side encryption"
fi

BUCKET_POLICY="$(aws s3api get-bucket-policy \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION" \
  --query 'Policy' \
  --output text 2>/dev/null || true)"

if echo "$BUCKET_POLICY" | grep -q "cloudfront.amazonaws.com" &&
   echo "$BUCKET_POLICY" | grep -q "$DISTRIBUTION_ID" &&
   echo "$BUCKET_POLICY" | grep -q "s3:GetObject"; then
  pass "S3 CloudFront access policy"
else
  fail "S3 CloudFront access policy"
fi

echo
echo "Checking CloudFront..."

DISTRIBUTION_STATUS="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.Status' \
  --output text)"

DISTRIBUTION_ENABLED="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DistributionConfig.Enabled' \
  --output text)"

if [ "$DISTRIBUTION_STATUS" = "Deployed" ]; then
  pass "CloudFront distribution deployed"
else
  fail "CloudFront distribution deployed (status: $DISTRIBUTION_STATUS)"
fi

if [ "$DISTRIBUTION_ENABLED" = "True" ]; then
  pass "CloudFront distribution enabled"
else
  fail "CloudFront distribution enabled"
fi

ROOT_OBJECT="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DistributionConfig.DefaultRootObject' \
  --output text)"

if [ "$ROOT_OBJECT" = "index.html" ]; then
  pass "CloudFront default root object"
else
  fail "CloudFront default root object"
fi

HTTPS_POLICY="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DistributionConfig.DefaultCacheBehavior.ViewerProtocolPolicy' \
  --output text)"

if [ "$HTTPS_POLICY" = "redirect-to-https" ]; then
  pass "CloudFront HTTPS redirect"
else
  fail "CloudFront HTTPS redirect"
fi

TLS_VERSION="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DistributionConfig.ViewerCertificate.MinimumProtocolVersion' \
  --output text)"

if [ "$TLS_VERSION" = "TLSv1.2_2021" ]; then
  pass "CloudFront minimum TLS version"
else
  fail "CloudFront minimum TLS version (actual: $TLS_VERSION)"
fi

IPV6_ENABLED="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DistributionConfig.IsIPV6Enabled' \
  --output text)"

if [ "$IPV6_ENABLED" = "True" ]; then
  pass "CloudFront IPv6"
else
  fail "CloudFront IPv6"
fi

OAC_ID="$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DistributionConfig.Origins.Items[0].OriginAccessControlId' \
  --output text)"

if [ -n "$OAC_ID" ] && [ "$OAC_ID" != "None" ]; then
  pass "CloudFront Origin Access Control attached"
else
  fail "CloudFront Origin Access Control attached"
fi

echo
echo "Checking CloudFront OAC..."

OAC_TYPE="$(aws cloudfront get-origin-access-control \
  --id "$OAC_ID" \
  --query 'OriginAccessControl.OriginAccessControlConfig.OriginAccessControlOriginType' \
  --output text)"

OAC_SIGNING="$(aws cloudfront get-origin-access-control \
  --id "$OAC_ID" \
  --query 'OriginAccessControl.OriginAccessControlConfig.SigningProtocol' \
  --output text)"

OAC_BEHAVIOR="$(aws cloudfront get-origin-access-control \
  --id "$OAC_ID" \
  --query 'OriginAccessControl.OriginAccessControlConfig.SigningBehavior' \
  --output text)"

if [ "$OAC_TYPE" = "s3" ]; then
  pass "OAC origin type"
else
  fail "OAC origin type"
fi

if [ "$OAC_SIGNING" = "sigv4" ]; then
  pass "OAC SigV4 signing"
else
  fail "OAC SigV4 signing"
fi

if [ "$OAC_BEHAVIOR" = "always" ]; then
  pass "OAC signing behavior"
else
  fail "OAC signing behavior"
fi

echo
echo "Checking CloudWatch..."

if aws cloudwatch get-dashboard \
  --dashboard-name "${PROJECT_NAME}-dashboard" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  pass "CloudWatch dashboard"
else
  fail "CloudWatch dashboard"
fi

ALARM_4XX="$(aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT_NAME}-cloudfront-4xx" \
  --region "$AWS_REGION" \
  --query 'MetricAlarms[0].AlarmName' \
  --output text)"

if [ "$ALARM_4XX" = "${PROJECT_NAME}-cloudfront-4xx" ]; then
  pass "CloudFront 4xx alarm"
else
  fail "CloudFront 4xx alarm"
fi

ALARM_5XX="$(aws cloudwatch describe-alarms \
  --alarm-names "${PROJECT_NAME}-cloudfront-5xx" \
  --region "$AWS_REGION" \
  --query 'MetricAlarms[0].AlarmName' \
  --output text)"

if [ "$ALARM_5XX" = "${PROJECT_NAME}-cloudfront-5xx" ]; then
  pass "CloudFront 5xx alarm"
else
  fail "CloudFront 5xx alarm"
fi

echo
echo "========================================"
echo "Validation Summary"
echo "========================================"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
else
  echo "VALIDATION FAILED"
  exit 1
fi