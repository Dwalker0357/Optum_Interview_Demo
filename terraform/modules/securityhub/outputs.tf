# Security Hub Module Outputs

output "security_hub_arn" {
  description = "ARN of the Security Hub account"
  value       = var.enable_security_hub ? aws_securityhub_account.main[0].arn : null
}

output "sns_topic_arn" {
  description = "ARN of the Security Hub alerts SNS topic"
  value       = var.enable_security_hub ? aws_sns_topic.security_hub_alerts[0].arn : null
}

output "dashboard_name" {
  description = "Name of the Security Hub CloudWatch dashboard"
  value       = var.enable_security_hub ? aws_cloudwatch_dashboard.security_hub[0].dashboard_name : null
}
