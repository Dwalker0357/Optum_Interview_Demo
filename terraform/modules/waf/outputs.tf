# WAF Module Outputs

output "web_acl_id" {
  description = "The ID of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_arn" {
  description = "The ARN of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_name" {
  description = "The name of the WAF Web ACL"
  value       = aws_wafv2_web_acl.main.name
}

output "allowed_ip_set_arn" {
  description = "The ARN of the allowed IP set"
  value       = length(aws_wafv2_ip_set.allowed_ips) > 0 ? aws_wafv2_ip_set.allowed_ips[0].arn : null
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for WAF"
  value       = aws_cloudwatch_log_group.waf.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for WAF alerts"
  value       = aws_sns_topic.waf_alerts.arn
}
