```bash
#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="us-east-1"
STATE_BUCKET="aliaa-personal-website-tfstate"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../terraform" && pwd)"

cd "$TERRAFORM_DIR"

echo "========================================"
echo "Personal Website Infrastructure Cleanup"
echo "========================================"
echo

echo "WARNING:"
echo "This will destroy the AWS infrastructure and Terraform state backend."
echo
read -r -p "Type 'destroy' to continue: " CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo
echo "Reading website bucket..."

BUCKET_NAME="$(terraform output -raw website_bucket_name 2>/dev/null || true)"

if [ -n "$BUCKET_NAME" ]; then
  echo "Website bucket: $BUCKET_NAME"

  echo
  echo "Deleting current objects..."

  aws s3 rm "s3://$BUCKET_NAME" \
    --recursive \
    --region "$AWS_REGION"

  echo
  echo "Deleting website bucket versions and delete markers..."

  while IFS= read -r object; do
    KEY="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Key"])')"
    VERSION_ID="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["VersionId"])')"

    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --key "$KEY" \
      --version-id "$VERSION_ID" \
      --region "$AWS_REGION" >/dev/null
  done < <(
    aws s3api list-object-versions \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --query 'Versions[].{Key:Key,VersionId:VersionId}' \
      --output json |
      python3 -c '
import sys
import json

data = json.load(sys.stdin)

for item in data:
    print(json.dumps(item))
'
  )

  while IFS= read -r object; do
    KEY="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Key"])')"
    VERSION_ID="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["VersionId"])')"

    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --key "$KEY" \
      --version-id "$VERSION_ID" \
      --region "$AWS_REGION" >/dev/null
  done < <(
    aws s3api list-object-versions \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
      --output json |
      python3 -c '
import sys
import json

data = json.load(sys.stdin)

for item in data:
    print(json.dumps(item))
'
  )

  echo "Website bucket emptied."
else
  echo "Website bucket output not found."
  echo "Terraform destroy will continue."
fi

echo
echo "Running Terraform destroy..."

terraform destroy

echo
echo "========================================"
echo "Deleting Terraform state backend"
echo "========================================"
echo

if aws s3api head-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" 2>/dev/null; then

  echo "State bucket found: $STATE_BUCKET"

  echo
  echo "Deleting state bucket objects..."

  aws s3 rm "s3://$STATE_BUCKET" \
    --recursive \
    --region "$AWS_REGION"

  echo
  echo "Deleting state bucket versions and delete markers..."

  while IFS= read -r object; do
    KEY="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Key"])')"
    VERSION_ID="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["VersionId"])')"

    aws s3api delete-object \
      --bucket "$STATE_BUCKET" \
      --key "$KEY" \
      --version-id "$VERSION_ID" \
      --region "$AWS_REGION" >/dev/null
  done < <(
    aws s3api list-object-versions \
      --bucket "$STATE_BUCKET" \
      --region "$AWS_REGION" \
      --query 'Versions[].{Key:Key,VersionId:VersionId}' \
      --output json |
      python3 -c '
import sys
import json

data = json.load(sys.stdin)

for item in data:
    print(json.dumps(item))
'
  )

  while IFS= read -r object; do
    KEY="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["Key"])')"
    VERSION_ID="$(echo "$object" | python3 -c 'import sys, json; print(json.load(sys.stdin)["VersionId"])')"

    aws s3api delete-object \
      --bucket "$STATE_BUCKET" \
      --key "$KEY" \
      --version-id "$VERSION_ID" \
      --region "$AWS_REGION" >/dev/null
  done < <(
    aws s3api list-object-versions \
      --bucket "$STATE_BUCKET" \
      --region "$AWS_REGION" \
      --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
      --output json |
      python3 -c '
import sys
import json

data = json.load(sys.stdin)

for item in data:
    print(json.dumps(item))
'
  )

  echo
  echo "Deleting state bucket..."

  aws s3api delete-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$AWS_REGION"

  echo "State backend deleted: $STATE_BUCKET"
else
  echo "State backend bucket not found."
  echo "Nothing to delete."
fi

echo
echo "========================================"
echo "Cleanup completed."
echo "========================================"
echo
echo "Infrastructure and Terraform state backend were deleted."
```
