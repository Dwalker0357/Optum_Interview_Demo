# CloudWatch Monitoring Module
# Sets up comprehensive monitoring and alerting

resource "aws_cloudwatch_log_group" "main" {
  for_each = toset(["jenkins", "nessus", "applications", "vpc-flow-logs"])

  name              = "/aws/ec2/${var.name_prefix}/${each.key}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", "i-1234567890abcdef0"],
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "EC2 Instance CPU"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = toset(var.jenkins_instances)

  alarm_name          = "${var.name_prefix}-high-cpu-${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"

  dimensions = {
    InstanceId = each.key
  }

  tags = var.tags
}
