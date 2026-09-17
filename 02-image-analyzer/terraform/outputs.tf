output "lambda_function_name" {
  description = "Name of the image analyzer Lambda function."
  value       = aws_lambda_function.image_analyzer.function_name
}

output "api_gateway_id" {
  description = "ID of the Image Analyzer API Gateway REST API."
  value       = aws_api_gateway_rest_api.image_analyzer.id
}

output "api_gateway_invoke_url" {
  description = "Base invoke URL for the Image Analyzer API."
  value       = "https://${aws_api_gateway_rest_api.image_analyzer.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}

output "friendly_endpoint" {
  description = "POST endpoint for image friendliness analysis."
  value       = "https://${aws_api_gateway_rest_api.image_analyzer.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/friendly"
}