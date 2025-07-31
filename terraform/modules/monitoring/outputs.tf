output "log_groups" {
  description = "CloudWatch log group names"
  value = {
    for k, v in aws_cloudwatch_log_group.main : k => v.name
  }
}

output "dashboards" {
  description = "CloudWatch dashboard names"
  value       = [aws_cloudwatch_dashboard.main.dashboard_name]
}

output "alarms" {
  description = "CloudWatch alarm names"
  value = {
    for k, v in aws_cloudwatch_metric_alarm.high_cpu : k => v.alarm_name
  }
}
