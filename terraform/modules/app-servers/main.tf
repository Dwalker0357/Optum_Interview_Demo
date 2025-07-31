# Application Servers with Intentional Vulnerabilities for Nessus Testing

# Launch Template for App Servers
resource "aws_launch_template" "app_servers" {
  name_prefix   = "${var.name_prefix}-app-"
  image_id      = local.app_ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = var.app_server_instance_profile
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional" # Intentionally less secure for demo
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name    = "${var.name_prefix}-app-server"
      Type    = "application-server"
      Purpose = "vulnerability-testing"
    })
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    aws_region  = var.aws_region
    name_prefix = var.name_prefix
  }))

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-app-lt"
    Type = "launch-template"
  })
}

# Auto Scaling Group for App Servers
resource "aws_autoscaling_group" "app_servers" {
  name                      = "${var.name_prefix}-app-asg"
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.app_servers.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Note: IAM roles and instance profiles are now managed by the IAM module
# This eliminates duplication and ensures consistent permissions across the infrastructure

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app_servers" {
  name              = "/aws/ec2/app-servers/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-app-logs"
    Type = "cloudwatch-log-group"
  })
}

# SNS Topic for Vulnerability Alerts
resource "aws_sns_topic" "vulnerability_alerts" {
  name = "${var.name_prefix}-vulnerability-alerts"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-vuln-alerts"
    Type = "sns-topic"
  })
}

# CloudWatch Alarm for High CPU (might indicate scanning activity)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.name_prefix}-app-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors app server cpu utilization"
  alarm_actions       = [aws_sns_topic.vulnerability_alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app_servers.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-cpu-alarm"
    Type = "cloudwatch-alarm"
  })
}

# S3 Bucket for App Data (with intentional misconfigurations)
resource "aws_s3_bucket" "app_data" {
  count = var.create_vulnerable_s3 ? 1 : 0

  bucket = "${var.name_prefix}-app-data-${random_string.bucket_suffix.result}"

  tags = merge(var.common_tags, {
    Name    = "${var.name_prefix}-app-data"
    Type    = "s3-bucket"
    Purpose = "vulnerability-demo"
  })
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Intentionally permissive S3 bucket policy (for demo)
resource "aws_s3_bucket_policy" "app_data" {
  count = var.create_vulnerable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_data[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowReadAccess"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.app_data[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceVpc" = var.vpc_id
          }
        }
      }
    ]
  })
}

# S3 bucket versioning (enabled for compliance)
resource "aws_s3_bucket_versioning" "app_data" {
  count = var.create_vulnerable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_data[0].id
  versioning_configuration {
    status = "Enabled" # Fixed: Enable versioning for compliance
  }
}

# S3 bucket encryption (enabled for compliance)
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  count = var.create_vulnerable_s3 ? 1 : 0

  bucket = aws_s3_bucket.app_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # Enabled: Encryption for compliance
    }
  }
}

# Create some sample files with sensitive-looking data
resource "aws_s3_object" "sample_data" {
  count = var.create_vulnerable_s3 ? 3 : 0

  bucket = aws_s3_bucket.app_data[0].id
  key    = "sample-data-${count.index + 1}.txt"
  content = templatefile("${path.module}/sample-data.txt", {
    file_number = count.index + 1
    timestamp   = timestamp()
  })

  # AWS S3 object tag limit is 10, so only include minimal tags
  # Removed tags to fix "Object tags cannot be greater than 10" error
}
