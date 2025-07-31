# Jenkins Module Outputs

# Infrastructure outputs
output "jenkins_master_asg_name" {
  description = "Name of the Jenkins master Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_master.name
}

output "jenkins_agents_asg_name" {
  description = "Name of the Jenkins agents Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_agents.name
}

output "jenkins_master_security_group_id" {
  description = "Security Group ID for Jenkins master"
  value       = aws_security_group.jenkins_master.id
}

output "jenkins_agents_security_group_id" {
  description = "Security Group ID for Jenkins agents"
  value       = aws_security_group.jenkins_agents.id
}

output "efs_file_system_id" {
  description = "EFS File System ID for Jenkins persistent storage"
  value       = aws_efs_file_system.jenkins.id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.jenkins.dns_name
}

# S3 outputs
output "artifacts_bucket_name" {
  description = "Name of the S3 bucket for Jenkins artifacts"
  value       = aws_s3_bucket.jenkins_artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for Jenkins artifacts"
  value       = aws_s3_bucket.jenkins_artifacts.arn
}

output "artifacts_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.jenkins_artifacts.bucket_domain_name
}

# IAM outputs (passed through from IAM module)
output "jenkins_master_role_arn" {
  description = "ARN of the Jenkins master IAM role"
  value       = var.jenkins_master_role_arn
}

output "jenkins_agents_role_arn" {
  description = "ARN of the Jenkins agents IAM role"
  value       = var.jenkins_agent_role_arn
}

output "jenkins_master_instance_profile_name" {
  description = "Name of the Jenkins master instance profile"
  value       = var.jenkins_master_instance_profile
}

output "jenkins_agents_instance_profile_name" {
  description = "Name of the Jenkins agents instance profile"
  value       = var.jenkins_agent_instance_profile
}

# Launch template outputs
output "jenkins_master_launch_template_id" {
  description = "ID of the Jenkins master launch template"
  value       = aws_launch_template.jenkins_master.id
}

output "jenkins_agents_launch_template_id" {
  description = "ID of the Jenkins agents launch template"
  value       = aws_launch_template.jenkins_agents.id
}

output "jenkins_master_launch_template_version" {
  description = "Latest version of the Jenkins master launch template"
  value       = aws_launch_template.jenkins_master.latest_version
}

output "jenkins_agents_launch_template_version" {
  description = "Latest version of the Jenkins agents launch template"
  value       = aws_launch_template.jenkins_agents.latest_version
}

# CloudWatch outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Jenkins"
  value       = aws_cloudwatch_log_group.jenkins.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Jenkins"
  value       = aws_cloudwatch_log_group.jenkins.arn
}

# Auto Scaling Policy outputs
output "agents_scale_up_policy_arn" {
  description = "ARN of the scale up policy for Jenkins agents"
  value       = aws_autoscaling_policy.agents_scale_up.arn
}

output "agents_scale_down_policy_arn" {
  description = "ARN of the scale down policy for Jenkins agents"
  value       = aws_autoscaling_policy.agents_scale_down.arn
}

# CloudWatch Alarm outputs
output "jenkins_master_cpu_alarm_name" {
  description = "Name of the Jenkins master CPU alarm"
  value       = aws_cloudwatch_metric_alarm.jenkins_master_cpu.alarm_name
}

output "jenkins_agents_cpu_alarm_name" {
  description = "Name of the Jenkins agents CPU alarm"
  value       = aws_cloudwatch_metric_alarm.jenkins_agents_cpu.alarm_name
}

output "agents_cpu_high_alarm_name" {
  description = "Name of the agents CPU high alarm"
  value       = aws_cloudwatch_metric_alarm.agents_cpu_high.alarm_name
}

output "agents_cpu_low_alarm_name" {
  description = "Name of the agents CPU low alarm"
  value       = aws_cloudwatch_metric_alarm.agents_cpu_low.alarm_name
}

# Configuration outputs
output "jenkins_url" {
  description = "Jenkins URL (internal)"
  value       = "http://jenkins.${var.environment}.internal:8080"
}

output "jenkins_port" {
  description = "Jenkins web interface port"
  value       = 8080
}

output "jenkins_agent_port" {
  description = "Jenkins agent communication port"
  value       = 50000
}

output "jenkins_home_path" {
  description = "Jenkins home directory path"
  value       = "/var/lib/jenkins"
}

# Deployment information
output "deployment_mode" {
  description = "Current deployment mode"
  value       = var.deployment_mode
}

output "spot_instances_enabled" {
  description = "Whether spot instances are enabled for agents"
  value       = var.deployment_mode == "demo" ? true : var.enable_spot_instances
}

# Resource counts
output "jenkins_master_instances" {
  description = "Number of Jenkins master instances (always 1)"
  value       = 1
}

output "jenkins_agents_min_capacity" {
  description = "Minimum number of Jenkins agent instances"
  value       = var.agents_config.min_size
}

output "jenkins_agents_max_capacity" {
  description = "Maximum number of Jenkins agent instances"
  value       = var.agents_config.max_size
}

output "jenkins_agents_desired_capacity" {
  description = "Desired number of Jenkins agent instances"
  value       = var.agents_config.desired_capacity
}

# Integration outputs
output "nessus_webhook_enabled" {
  description = "Whether Nessus webhook integration is enabled"
  value       = var.nessus_integration.enabled
}

output "nessus_webhook_path" {
  description = "Nessus webhook path"
  value       = var.nessus_integration.webhook_path
}

# Backup configuration
output "backup_enabled" {
  description = "Whether automated backup is enabled"
  value       = var.enable_backup
}

output "backup_schedule" {
  description = "Backup schedule (cron expression)"
  value       = var.backup_schedule
}

# Storage configuration
output "artifact_retention_days" {
  description = "Number of days artifacts are retained"
  value       = var.artifact_retention_days
}

output "log_retention_days" {
  description = "Number of days logs are retained"
  value       = var.log_retention_days
}

# Plugin information
output "installed_plugins" {
  description = "List of Jenkins plugins that will be installed"
  value       = var.jenkins_plugins
}

output "seed_jobs_count" {
  description = "Number of seed jobs configured"
  value       = length(var.seed_jobs)
}

# Network configuration
output "efs_mount_targets" {
  description = "List of EFS mount target IDs"
  value       = aws_efs_mount_target.jenkins[*].id
}

output "efs_security_group_id" {
  description = "Security Group ID for EFS"
  value       = aws_security_group.efs.id
}

# Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value = merge(var.tags, {
    Environment = var.environment
    Project     = var.project
    Module      = "jenkins"
    ManagedBy   = "terraform"
  })
}
