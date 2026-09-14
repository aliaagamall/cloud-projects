#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
REPORT_FILE="$PROJECT_DIR/reports/monitoring-report.md"

REGION="us-east-1"
METRIC_REGION="Global"
NAMESPACE="AWS/CloudFront"
PERIOD=300
LOOKBACK_HOURS=1

DISTRIBUTION_ID="$(cd "$TERRAFORM_DIR" && terraform output -raw cloudfront_distribution_id)"
DOMAIN_NAME="$(cd "$TERRAFORM_DIR" && terraform output -raw cloudfront_domain_name)"

END_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
START_TIME="$(date -u -d "$LOOKBACK_HOURS hour ago" +"%Y-%m-%dT%H:%M:%SZ")"

get_metric_values() {
  local metric_name="$1"
  local statistic="$2"

  aws cloudwatch get-metric-statistics \
    --namespace "$NAMESPACE" \
    --metric-name "$metric_name" \
    --dimensions Name=DistributionId,Value="$DISTRIBUTION_ID" Name=Region,Value="$METRIC_REGION" \
    --start-time "$START_TIME" \
    --end-time "$END_TIME" \
    --period "$PERIOD" \
    --statistics "$statistic" \
    --region "$REGION" \
    --query "Datapoints[].$statistic" \
    --output text
}

REQUEST_VALUES="$(get_metric_values "Requests" "Sum")"
ERROR_4XX_VALUES="$(get_metric_values "4xxErrorRate" "Average")"
ERROR_5XX_VALUES="$(get_metric_values "5xxErrorRate" "Average")"

REQUESTS="$(awk '{sum=0; for (i=1; i<=NF; i++) sum += $i} END {print sum+0}' <<< "$REQUEST_VALUES")"

ERROR_4XX="$(awk '{sum=0; count=0; for (i=1; i<=NF; i++) {sum += $i; count++}} END {if (count > 0) printf "%.2f", sum/count; else print "0.00"}' <<< "$ERROR_4XX_VALUES")"

ERROR_5XX="$(awk '{sum=0; count=0; for (i=1; i<=NF; i++) {sum += $i; count++}} END {if (count > 0) printf "%.2f", sum/count; else print "0.00"}' <<< "$ERROR_5XX_VALUES")"

if awk "BEGIN {exit !($ERROR_4XX < 10)}"; then
  STATUS_4XX="Healthy"
else
  STATUS_4XX="Attention"
fi

if awk "BEGIN {exit !($ERROR_5XX < 5)}"; then
  STATUS_5XX="Healthy"
else
  STATUS_5XX="Attention"
fi

ALARM_4XX="$(aws cloudwatch describe-alarms \
  --alarm-names "personal-website-cloudfront-4xx" \
  --region "$REGION" \
  --query "MetricAlarms[0].StateValue" \
  --output text)"

ALARM_5XX="$(aws cloudwatch describe-alarms \
  --alarm-names "personal-website-cloudfront-5xx" \
  --region "$REGION" \
  --query "MetricAlarms[0].StateValue" \
  --output text)"

cat > "$REPORT_FILE" <<EOF
# Personal Website Monitoring Report

## Monitoring Period

- Start: $START_TIME
- End: $END_TIME
- Distribution: $DISTRIBUTION_ID
- CloudFront Domain: $DOMAIN_NAME

## CloudFront Metrics

| Metric | Value | Status |
|---|---:|---|
| Requests | $REQUESTS | Normal |
| 4xx Error Rate | $ERROR_4XX% | $STATUS_4XX |
| 5xx Error Rate | $ERROR_5XX% | $STATUS_5XX |

## CloudWatch Alarms

| Alarm | State |
|---|---|
| 4xx Error Alarm | $ALARM_4XX |
| 5xx Error Alarm | $ALARM_5XX |

## Summary

The website was monitored through Amazon CloudWatch using CloudFront metrics.

The report covers the last $LOOKBACK_HOURS hour of activity.

EOF

echo "Monitoring report generated:"
echo "$REPORT_FILE"