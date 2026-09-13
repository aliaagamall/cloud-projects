resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${local.name_prefix}-oac"
  description                       = "Origin Access Control for the private website S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}