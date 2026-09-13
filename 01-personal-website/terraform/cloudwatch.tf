resource "aws_cloudwatch_dashboard" "website" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          title   = "CloudFront Requests"
          region  = "us-east-1"
          view    = "timeSeries"
          stacked = false

          metrics = [
            [
              "AWS/CloudFront",
              "Requests",
              "DistributionId",
              aws_cloudfront_distribution.website.id,
              "Region",
              "Global"
            ]
          ]

          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          title   = "CloudFront 4xx Error Rate"
          region  = "us-east-1"
          view    = "timeSeries"
          stacked = false

          metrics = [
            [
              "AWS/CloudFront",
              "4xxErrorRate",
              "DistributionId",
              aws_cloudfront_distribution.website.id,
              "Region",
              "Global"
            ]
          ]

          period = 300
          stat   = "Average"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          title   = "CloudFront 5xx Error Rate"
          region  = "us-east-1"
          view    = "timeSeries"
          stacked = false

          metrics = [
            [
              "AWS/CloudFront",
              "5xxErrorRate",
              "DistributionId",
              aws_cloudfront_distribution.website.id,
              "Region",
              "Global"
            ]
          ]

          period = 300
          stat   = "Average"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  alarm_name          = "${local.name_prefix}-cloudfront-5xx"
  alarm_description   = "Alarm when CloudFront 5xx error rate is elevated."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5

  dimensions = {
    DistributionId = aws_cloudfront_distribution.website.id
    Region         = "Global"
  }

  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx" {
  alarm_name          = "${local.name_prefix}-cloudfront-4xx"
  alarm_description   = "Alarm when CloudFront 4xx error rate is elevated."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 10

  dimensions = {
    DistributionId = aws_cloudfront_distribution.website.id
    Region         = "Global"
  }

  treat_missing_data = "notBreaching"
}