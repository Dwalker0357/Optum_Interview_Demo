# Drift Detection Module Outputs

output "lambda_function_arn" {
  description = "ARN of the drift detection Lambda function"
  value       = var.enable_drift_detection ? aws_lambda_function.drift_detector[0].arn : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for drift detection"
  value       = var.enable_drift_detection ? aws_cloudwatch_event_rule.drift_detection[0].arn : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for drift alerts"
  value       = var.enable_drift_detection ? aws_sns_topic.drift_alerts[0].arn : null
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for drift reports"
  value       = var.enable_drift_detection ? aws_s3_bucket.drift_reports[0].bucket : null
}
