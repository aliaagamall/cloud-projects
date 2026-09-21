resource "aws_s3_bucket" "content" {
  for_each = toset(["en", "es"])

  bucket = "${var.project_name}-${var.environment}-${each.key}"

  tags = {
    Language = each.key
    Purpose  = "translated-content"
  }
}

resource "aws_s3_bucket_public_access_block" "content" {
  for_each = aws_s3_bucket.content

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "content" {
  for_each = aws_s3_bucket.content

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "content" {
  for_each = aws_s3_bucket.content

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  for_each = aws_s3_bucket.content

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
