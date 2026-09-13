# s3 outputs
output "website_bucket_name" {
  description = "Name of the private S3 bucket used for website assets."
  value       = aws_s3_bucket.website.bucket
}

output "website_bucket_arn" {
  description = "ARN of the private S3 bucket used for website assets."
  value       = aws_s3_bucket.website.arn
}

#cloudfront outputs
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution."
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution."
  value       = aws_cloudfront_distribution.website.domain_name
}