resource "aws_api_gateway_rest_api" "image_analyzer" {
  name        = "${var.project_name}-api"
  description = "API for analyzing profile photo friendliness."
}

resource "aws_api_gateway_resource" "friendly" {
  rest_api_id = aws_api_gateway_rest_api.image_analyzer.id
  parent_id   = aws_api_gateway_rest_api.image_analyzer.root_resource_id
  path_part   = "friendly"
}

resource "aws_api_gateway_method" "friendly_post" {
  rest_api_id   = aws_api_gateway_rest_api.image_analyzer.id
  resource_id   = aws_api_gateway_resource.friendly.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "friendly_post" {
  rest_api_id             = aws_api_gateway_rest_api.image_analyzer.id
  resource_id             = aws_api_gateway_resource.friendly.id
  http_method             = aws_api_gateway_method.friendly_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.image_analyzer.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_analyzer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.image_analyzer.execution_arn}/*/POST/friendly"
}

resource "aws_api_gateway_deployment" "image_analyzer" {
  rest_api_id = aws_api_gateway_rest_api.image_analyzer.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.friendly.id,
      aws_api_gateway_method.friendly_post.id,
      aws_api_gateway_integration.friendly_post.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.friendly_post
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.image_analyzer.id
  deployment_id = aws_api_gateway_deployment.image_analyzer.id
  stage_name    = "prod"
}