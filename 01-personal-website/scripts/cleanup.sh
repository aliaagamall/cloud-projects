#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

AWS_REGION="us-east-1"
STATE_BUCKET="aliaa-personal-website-tfstate"

delete_all_versions() {
  local bucket="$1"

  if ! aws s3api head-bucket \
    --bucket "$bucket" \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "Bucket does not exist: $bucket"
    return 0
  fi

  echo "Removing all object versions and delete markers from: $bucket"

  while true; do
    delete_payload="$(
      aws s3api list-object-versions \
        --bucket "$bucket" \
        --region "$AWS_REGION" \
        --output json |
      python3 -c '
import json
import sys

data = json.load(sys.stdin)

objects = [
    {"Key": item["Key"], "VersionId": item["VersionId"]}
    for item in data.get("Versions", [])
]

objects.extend(
    {"Key": item["Key"], "VersionId": item["VersionId"]}
    for item in data.get("DeleteMarkers", [])
)

print(json.dumps({"Objects": objects, "Quiet": True}))
'
    )"

    object_count="$(
      python3 -c '
import json
import sys

data = json.load(sys.stdin)
print(len(data["Objects"]))
' <<< "$delete_payload"
    )"

    if [ "$object_count" -eq 0 ]; then
      break
    fi

    aws s3api delete-objects \
      --bucket "$bucket" \
      --region "$AWS_REGION" \
      --delete "$delete_payload" >/dev/null

    echo "Deleted $object_count versioned objects/markers."
  done
}

echo "========================================"
echo "Personal Website Cleanup"
echo "========================================"
echo

echo "Terraform directory:"
echo "$TERRAFORM_DIR"
echo

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: Terraform is not installed."
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: AWS CLI is not installed."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: Python 3 is not installed."
  exit 1
fi

echo "Checking AWS authentication..."
aws sts get-caller-identity >/dev/null
echo "AWS authentication: OK"
echo

cd "$TERRAFORM_DIR"

echo "Checking Terraform state..."
if ! terraform state list >/dev/null 2>&1; then
  echo "Error: Terraform state is not available."
  echo "Run setup-terraform.sh before using cleanup.sh."
  exit 1
fi

BUCKET_NAME="$(terraform output -raw website_bucket_name)"

if [ -z "$BUCKET_NAME" ]; then
  echo "Error: Could not determine website bucket name."
  exit 1
fi

echo "Website bucket: $BUCKET_NAME"
echo "Terraform state bucket: $STATE_BUCKET"
echo

read -r -p "Type 'destroy' to confirm cleanup: " CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo
echo "Step 1/3: Emptying website bucket..."
delete_all_versions "$BUCKET_NAME"
echo "Website bucket is empty."
echo

echo "Step 2/3: Destroying Terraform-managed infrastructure..."
terraform destroy -auto-approve
echo "Terraform resources destroyed."
echo

echo "Step 3/3: Removing Terraform state backend..."
delete_all_versions "$STATE_BUCKET"

if aws s3api head-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" >/dev/null 2>&1; then

  aws s3api delete-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$AWS_REGION"

  echo "Terraform state bucket deleted."
else
  echo "Terraform state bucket does not exist."
fi

echo
echo "========================================"
echo "Cleanup completed successfully."
echo "========================================"