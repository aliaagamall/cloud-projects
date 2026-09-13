output "website_bucket_name" {
  description = "Name of the private S3 bucket used for website assets."
  value       = aws_s3_bucket.website.bucket
}

output "website_bucket_arn" {
  description = "ARN of the private S3 bucket used for website assets."
  value       = aws_s3_bucket.website.arn
}