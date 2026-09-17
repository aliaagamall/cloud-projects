data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../application/lambda/handler.py"
  output_path = "${path.module}/image-analyzer-lambda.zip"
}

resource "aws_lambda_function" "image_analyzer" {
  function_name = "${var.project_name}-function"
  role          = aws_iam_role.lambda_execution.arn

  runtime = "python3.13"
  handler = "handler.lambda_handler"

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  timeout     = 30
  memory_size = 256

  architectures = ["x86_64"]
}