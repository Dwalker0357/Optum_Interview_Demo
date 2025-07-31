output "app_servers_asg_name" {
  description = "Name of the app servers Auto Scaling Group"
  value       = aws_autoscaling_group.app_servers.name
}

output "app_servers_asg_arn" {
  description = "ARN of the app servers Auto Scaling Group"
  value       = aws_autoscaling_group.app_servers.arn
}

output "app_servers_launch_template_id" {
  description = "ID of the app servers launch template"
  value       = aws_launch_template.app_servers.id
}

output "app_servers_iam_role_arn" {
  description = "ARN of the app servers IAM role"
  value       = var.app_server_role_arn
}

output "app_servers_iam_role_name" {
  description = "Name of the app servers IAM role"
  value       = var.app_server_role_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app_servers.name
}

output "vulnerability_alerts_topic_arn" {
  description = "ARN of the SNS topic for vulnerability alerts"
  value       = aws_sns_topic.vulnerability_alerts.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket with intentional vulnerabilities (if created)"
  value       = var.create_vulnerable_s3 ? aws_s3_bucket.app_data[0].id : ""
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket with intentional vulnerabilities (if created)"
  value       = var.create_vulnerable_s3 ? aws_s3_bucket.app_data[0].arn : ""
}

output "application_urls" {
  description = "URLs for accessing the vulnerable application"
  value = {
    main_page     = "http://<instance-ip>/"
    php_info      = "http://<instance-ip>/phpinfo.php"
    health_check  = "http://<instance-ip>/health"
    server_status = "http://<instance-ip>/server-status"
    uploads_dir   = "http://<instance-ip>/uploads/"
  }
}

output "vulnerability_summary" {
  description = "Summary of intentional vulnerabilities for testing"
  value = {
    web_vulnerabilities = [
      "SQL Injection simulation",
      "Cross-Site Scripting (XSS)",
      "Information disclosure (phpinfo)",
      "Weak authentication (admin/password)",
      "Directory listing enabled",
      "Server information exposure"
    ]
    network_vulnerabilities = [
      "Telnet service enabled",
      "FTP service with anonymous access",
      "SSH with password authentication",
      "Weak user accounts (testuser/password123)"
    ]
    system_vulnerabilities = [
      "Overly permissive IAM policies",
      "Unencrypted S3 bucket",
      "Sensitive files in /var/backups",
      "Instance metadata v1 enabled"
    ]
  }
}

output "scanning_targets" {
  description = "Information for Nessus scanning configuration"
  value = {
    scan_ports = [
      "21 (FTP)",
      "22 (SSH)",
      "23 (Telnet)",
      "80 (HTTP)",
      "443 (HTTPS)"
    ]
    scan_credentials = {
      ssh_users  = ["testuser:password123", "admin:admin"]
      ftp_access = "anonymous access enabled"
    }
    vulnerable_endpoints = [
      "/phpinfo.php",
      "/server-status",
      "/uploads/",
      "/?search=<script>alert('xss')</script>"
    ]
  }
}

output "monitoring_info" {
  description = "Monitoring and alerting information"
  value = {
    cloudwatch_log_group = aws_cloudwatch_log_group.app_servers.name
    sns_topic            = aws_sns_topic.vulnerability_alerts.arn
    cpu_alarm_threshold  = "80%"
    log_retention_days   = var.log_retention_days
  }
}
