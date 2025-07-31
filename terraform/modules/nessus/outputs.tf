# Instance and Infrastructure Outputs
output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.nessus.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.nessus.arn
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.nessus.id
}

output "launch_template_latest_version" {
  description = "Latest version of the launch template"
  value       = aws_launch_template.nessus.latest_version
}

# Security Group Outputs
output "nessus_security_group_id" {
  description = "Security group ID for Nessus instances"
  value       = aws_security_group.nessus.id
}

output "efs_security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}

# Storage Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for scan reports"
  value       = aws_s3_bucket.nessus_reports.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for scan reports"
  value       = aws_s3_bucket.nessus_reports.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.nessus_reports.bucket_domain_name
}

output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.nessus_shared.id
}

output "efs_file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.nessus_shared.arn
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.nessus_shared.dns_name
}

# IAM Outputs
output "nessus_role_arn" {
  description = "ARN of the Nessus IAM role"
  value       = aws_iam_role.nessus.arn
}

output "nessus_role_name" {
  description = "Name of the Nessus IAM role"
  value       = aws_iam_role.nessus.name
}

output "nessus_instance_profile_arn" {
  description = "ARN of the Nessus instance profile"
  value       = aws_iam_instance_profile.nessus.arn
}

output "nessus_instance_profile_name" {
  description = "Name of the Nessus instance profile"
  value       = aws_iam_instance_profile.nessus.name
}

# Secrets Manager Outputs
output "nessus_license_secret_arn" {
  description = "ARN of the Nessus license secret"
  value       = aws_secretsmanager_secret.nessus_license.arn
}

output "nessus_license_secret_name" {
  description = "Name of the Nessus license secret"
  value       = aws_secretsmanager_secret.nessus_license.name
}

# Network Load Balancer Outputs
output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.nessus.dns_name
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.nessus.arn
}

output "nessus_url" {
  description = "Direct URL to access Nessus web interface"
  value       = "https://${aws_lb.nessus.dns_name}:8834/"
}

output "target_group_arn" {
  description = "ARN of the TCP target group"
  value       = aws_lb_target_group.nessus_tcp.arn
}

output "target_group_name" {
  description = "Name of the TCP target group"
  value       = aws_lb_target_group.nessus_tcp.name
}

# CloudWatch Outputs
output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.nessus.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.nessus.arn
}

output "scale_up_policy_arn" {
  description = "ARN of the scale up policy"
  value       = aws_autoscaling_policy.scale_up.arn
}

output "scale_down_policy_arn" {
  description = "ARN of the scale down policy"
  value       = aws_autoscaling_policy.scale_down.arn
}

# SNS Outputs
output "alerts_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.nessus_alerts.arn
}

output "alerts_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.nessus_alerts.name
}

# Lambda Outputs (Demo Mode)
output "scheduler_lambda_function_name" {
  description = "Name of the scheduler Lambda function (demo mode only)"
  value       = var.demo_mode ? aws_lambda_function.nessus_scheduler[0].function_name : null
}

output "scheduler_lambda_function_arn" {
  description = "ARN of the scheduler Lambda function (demo mode only)"
  value       = var.demo_mode ? aws_lambda_function.nessus_scheduler[0].arn : null
}

# EventBridge Outputs (Demo Mode)
output "start_schedule_rule_name" {
  description = "Name of the EventBridge rule for starting scanners (demo mode only)"
  value       = var.demo_mode ? aws_cloudwatch_event_rule.start_scanners[0].name : null
}

output "stop_schedule_rule_name" {
  description = "Name of the EventBridge rule for stopping scanners (demo mode only)"
  value       = var.demo_mode ? aws_cloudwatch_event_rule.stop_scanners[0].name : null
}

# Configuration Outputs
output "nessus_admin_username" {
  description = "Nessus admin username"
  value       = var.nessus_admin_username
}

output "nessus_admin_password_secret_key" {
  description = "Secret key for retrieving Nessus admin password"
  value       = "admin_password"
  sensitive   = true
}

# Scanning Configuration Outputs
output "scan_policies_configured" {
  description = "List of configured scan policies"
  value       = keys(var.scan_policies)
}

output "scan_schedule" {
  description = "Default scan schedule"
  value       = var.scan_schedule
}

# URLs and Endpoints
output "webhook_endpoints" {
  description = "Available webhook endpoints for integration"
  value = {
    scan_trigger = "/api/v1/scan/trigger"
    scan_status  = "/api/v1/scan/status"
    reports      = "/api/v1/reports"
  }
}

# Demo Mode Configuration
output "demo_mode_enabled" {
  description = "Whether demo mode is enabled"
  value       = var.demo_mode
}

output "demo_start_schedule" {
  description = "Demo mode start schedule"
  value       = var.demo_mode ? var.demo_start_schedule : null
}

output "demo_stop_schedule" {
  description = "Demo mode stop schedule"
  value       = var.demo_mode ? var.demo_stop_schedule : null
}

# Cost Optimization Outputs
output "spot_instances_enabled" {
  description = "Whether spot instances are enabled"
  value       = var.enable_spot_instances
}

output "report_retention_days" {
  description = "Number of days reports are retained"
  value       = var.report_retention_days
}

# Monitoring Outputs
output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names"
  value = [
    aws_cloudwatch_metric_alarm.high_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.low_cpu.alarm_name
  ]
}

# Network Configuration
output "vpc_id" {
  description = "VPC ID where Nessus is deployed"
  value       = var.vpc_id
}

output "subnets_used" {
  description = "List of subnet IDs used by the Auto Scaling Group"
  value       = data.aws_subnets.private.ids
}

# Integration Status
output "jenkins_integration_enabled" {
  description = "Whether Jenkins integration is enabled"
  value       = var.jenkins_webhook_url != ""
}

output "cve_feed_enabled" {
  description = "Whether CVE feed is enabled"
  value       = var.enable_cve_feed
}

output "auto_update_plugins_enabled" {
  description = "Whether automatic plugin updates are enabled"
  value       = var.auto_update_plugins
}

# Compliance Configuration
output "compliance_frameworks_enabled" {
  description = "List of enabled compliance frameworks"
  value       = var.compliance_frameworks
}

output "compliance_reports_enabled" {
  description = "Whether compliance reports are enabled"
  value       = var.enable_compliance_reports
}

# Performance Configuration
output "scan_performance_level" {
  description = "Configured scan performance level"
  value       = var.scan_performance_level
}

output "max_concurrent_scans" {
  description = "Maximum concurrent scans per instance"
  value       = var.max_concurrent_scans
}

output "parallel_hosts_scanning" {
  description = "Number of hosts scanned in parallel"
  value       = var.parallel_hosts_scanning
}

# Quick Reference
output "quick_start_guide" {
  description = "Quick start information for using the Nessus deployment"
  value = {
    nessus_url               = "https://${aws_lb.nessus.dns_name}:8834/"
    admin_credentials_secret = aws_secretsmanager_secret.nessus_license.name
    s3_reports_bucket        = aws_s3_bucket.nessus_reports.bucket
    log_group                = aws_cloudwatch_log_group.nessus.name
    target_group             = aws_lb_target_group.nessus_tcp.name
    demo_mode                = var.demo_mode
  }
}
