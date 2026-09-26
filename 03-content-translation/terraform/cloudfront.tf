resource "aws_cloudfront_cache_policy" "content" {
  name        = "${var.project_name}-${var.environment}-content"
  comment     = "Cache policy for ${var.project_name}-${var.environment} content"
  default_ttl = 60
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"

      headers {
        items = ["Accept-Language"]
      }
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

resource "aws_cloudfront_distribution" "content" {
  enabled = true

  comment = "${var.project_name}-${var.environment}"

  default_root_object = "index.html"

  price_class = "PriceClass_100"

  dynamic "origin" {
    for_each = aws_s3_bucket.content

    content {
      domain_name = origin.value.bucket_regional_domain_name
      origin_id   = "s3-${origin.key}"

      s3_origin_config {
        origin_access_identity = aws_cloudfront_origin_access_identity.content.cloudfront_access_identity_path
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-${var.default_language}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id = aws_cloudfront_cache_policy.content.id
    compress        = true

    dynamic "lambda_function_association" {
      for_each = var.enable_language_routing ? [1] : []

      content {
        event_type   = "origin-request"
        lambda_arn   = aws_lambda_function.language_routing.qualified_arn
        include_body = false
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  is_ipv6_enabled = true
}
