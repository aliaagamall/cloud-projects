output "content_bucket_names" {
  description = "Names of the language-specific content buckets."
  value = {
    for language, bucket in aws_s3_bucket.content :
    language => bucket.bucket
  }
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.content.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.content.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.content.domain_name
}

output "cloudfront_url" {
  description = "CloudFront distribution URL."
  value       = "https://${aws_cloudfront_distribution.content.domain_name}"
}