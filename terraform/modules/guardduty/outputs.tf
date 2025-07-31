# GuardDuty Module Outputs

output "detector_id" {
  description = "The ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "detector_arn" {
  description = "The ARN of the GuardDuty detector"
  value       = aws_guardduty_detector.main.arn
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for GuardDuty findings"
  value       = aws_sns_topic.guardduty_findings.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for GuardDuty"
  value       = aws_cloudwatch_log_group.guardduty.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for GuardDuty findings"
  value       = aws_cloudwatch_event_rule.guardduty_findings.arn
}
