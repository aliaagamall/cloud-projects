resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.image_analyzer.function_name}"
  retention_in_days = 14
}