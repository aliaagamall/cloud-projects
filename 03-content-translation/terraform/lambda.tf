locals {
  language_origins = {
    for language, bucket in aws_s3_bucket.content :
    language => {
      domain_name = bucket.bucket_regional_domain_name
      region      = var.region
    }
  }

  lambda_edge_source = templatefile(
    "${path.module}/../lambda/language-routing/index.py.tftpl",
    {
      default_language       = var.default_language
      origins_json           = jsonencode(local.language_origins)
      origin_access_identity = aws_cloudfront_origin_access_identity.content.cloudfront_access_identity_path
    }
  )
}

data "archive_file" "language_routing" {
  type = "zip"

  source_content          = local.lambda_edge_source
  source_content_filename = "index.py"

  output_path = "${path.module}/../lambda/language-routing/language-routing.zip"
}

resource "aws_iam_role" "lambda_edge" {
  name = "${var.project_name}-${var.environment}-lambda-edge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_edge_basic" {
  role       = aws_iam_role.lambda_edge.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "language_routing" {
  provider = aws.edge

  function_name = "${var.project_name}-${var.environment}-language-routing"

  filename         = data.archive_file.language_routing.output_path
  source_code_hash = data.archive_file.language_routing.output_base64sha256

  role = aws_iam_role.lambda_edge.arn

  handler = "index.lambda_handler"
  runtime = "python3.13"

  publish = true
}
