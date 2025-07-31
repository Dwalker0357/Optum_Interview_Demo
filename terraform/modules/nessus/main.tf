# Nessus Vulnerability Scanner Module
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Data sources
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

# Random password for Nessus admin
resource "random_password" "nessus_admin" {
  length  = 16
  special = true
}

# S3 bucket for scan reports
resource "aws_s3_bucket" "nessus_reports" {
  bucket = "${var.project_name}-nessus-reports-${random_id.bucket_suffix.hex}"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-reports"
    Type = "VulnerabilityReports"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "nessus_reports" {
  bucket = aws_s3_bucket.nessus_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "nessus_reports" {
  bucket = aws_s3_bucket.nessus_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "nessus_reports" {
  bucket = aws_s3_bucket.nessus_reports.id

  rule {
    id     = "reports_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.report_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "nessus_reports" {
  bucket = aws_s3_bucket.nessus_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 object for bootstrap script (to work around 16KB user-data limit)
resource "aws_s3_object" "nessus_init_script" {
  bucket = aws_s3_bucket.nessus_reports.id
  key    = "bootstrap/nessus-init.sh"
  source = "${path.module}/userdata/nessus-init.sh"
  etag   = filemd5("${path.module}/userdata/nessus-init.sh")

  # AWS S3 object tag limit is 10, so no tags added
}

# EFS for shared storage
resource "aws_efs_file_system" "nessus_shared" {
  creation_token = "${var.project_name}-nessus-shared"

  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = 100

  encrypted = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-shared"
  })
}

resource "aws_efs_mount_target" "nessus_shared" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.nessus_shared.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# Security Groups
resource "aws_security_group" "nessus" {
  name        = "${var.project_name}-nessus-sg"
  description = "Security group for Nessus scanners"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS direct access for Nessus web interface"
    from_port   = 8834
    to_port     = 8834
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Restricted to developer IP for security
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-sg"
  })
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-nessus-efs-sg"
  description = "Security group for Nessus EFS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from Nessus instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.nessus_security_group_id != "" ? var.nessus_security_group_id : aws_security_group.nessus.id]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-efs-sg"
  })
}

# IAM Role for Nessus instances
resource "aws_iam_role" "nessus" {
  name = "${var.project_name}-nessus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "nessus" {
  name = "${var.project_name}-nessus-policy"
  role = aws_iam_role.nessus.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.nessus_reports.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.nessus_reports.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.nessus_license.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "nessus" {
  name = "${var.project_name}-nessus-profile"
  role = aws_iam_role.nessus.name
}

# Secrets Manager for Nessus Essentials
resource "aws_secretsmanager_secret" "nessus_license" {
  name        = "${var.project_name}-nessus-essentials"
  description = "Nessus Essentials activation code and configuration"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "nessus_license" {
  secret_id = aws_secretsmanager_secret.nessus_license.id
  secret_string = jsonencode({
    activation_code = var.nessus_activation_code
    admin_username  = var.nessus_admin_username
    admin_password  = random_password.nessus_admin.result
  })
}

# Launch Template
resource "aws_launch_template" "nessus" {
  name_prefix   = "${var.project_name}-nessus-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [var.nessus_security_group_id != "" ? var.nessus_security_group_id : aws_security_group.nessus.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.nessus.name
  }

  user_data = base64encode(templatefile("${path.module}/userdata/bootstrap.sh", {
    s3_bucket           = aws_s3_bucket.nessus_reports.bucket
    script_key          = aws_s3_object.nessus_init_script.key
    aws_region          = var.aws_region
    efs_id              = aws_efs_file_system.nessus_shared.id
    secret_arn          = aws_secretsmanager_secret.nessus_license.arn
    project_name        = var.project_name
    scan_schedule       = var.scan_schedule
    webhook_url         = var.jenkins_webhook_url
    cve_feed_enabled    = var.enable_cve_feed
    auto_update_plugins = var.auto_update_plugins
    NESSUS_VERSION      = "10.6.4"
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.project_name}-nessus-scanner"
      Type = "VulnerabilityScanner"
    })
  }

  tags = var.common_tags
}

# Auto Scaling Group
resource "aws_autoscaling_group" "nessus" {
  name                      = "${var.project_name}-nessus-asg"
  vpc_zone_identifier       = data.aws_subnets.private.ids
  target_group_arns         = [aws_lb_target_group.nessus_tcp.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_capacity
  max_size         = var.max_capacity
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.nessus.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-nessus-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-nessus-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nessus.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-nessus-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nessus.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-nessus-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors nessus cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nessus.name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-nessus-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "This metric monitors nessus cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nessus.name
  }

  tags = var.common_tags
}

# Network Load Balancer for TCP pass-through
resource "aws_lb" "nessus" {
  name               = "${var.project_name}-nessus-nlb"
  internal           = var.internal_lb
  load_balancer_type = "network"
  subnets            = var.internal_lb ? var.private_subnet_ids : var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-nlb"
  })
}

# TCP Target Group for direct Nessus access
resource "aws_lb_target_group" "nessus_tcp" {
  name     = "${var.project_name}-nessus-tcp-tg"
  port     = 8834
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 5
    interval            = 30
    port                = "traffic-port"
    protocol            = "TCP"
    timeout             = 10
    unhealthy_threshold = 2
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-tcp-tg"
  })
}

# NLB Listener for TCP pass-through
resource "aws_lb_listener" "nessus_tcp" {
  load_balancer_arn = aws_lb.nessus.arn
  port              = "8834"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nessus_tcp.arn
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nessus-listener"
  })
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "nessus" {
  name              = "/aws/nessus/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = var.common_tags
}

# Lambda function for scheduled operations
resource "aws_lambda_function" "nessus_scheduler" {
  count = var.demo_mode ? 1 : 0

  filename      = "${path.module}/lambda/nessus-scheduler.zip"
  function_name = "${var.project_name}-nessus-scheduler"
  role          = aws_iam_role.lambda_scheduler[0].arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 60

  environment {
    variables = {
      ASG_NAME = aws_autoscaling_group.nessus.name
    }
  }

  tags = var.common_tags
}

resource "aws_iam_role" "lambda_scheduler" {
  count = var.demo_mode ? 1 : 0
  name  = "${var.project_name}-nessus-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "lambda_scheduler" {
  count = var.demo_mode ? 1 : 0
  name  = "${var.project_name}-nessus-scheduler-policy"
  role  = aws_iam_role.lambda_scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rules for scheduling
resource "aws_cloudwatch_event_rule" "start_scanners" {
  count               = var.demo_mode ? 1 : 0
  name                = "${var.project_name}-start-nessus-scanners"
  description         = "Start Nessus scanners for demo mode"
  schedule_expression = var.demo_start_schedule

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "start_scanners" {
  count = var.demo_mode ? 1 : 0
  rule  = aws_cloudwatch_event_rule.start_scanners[0].name
  arn   = aws_lambda_function.nessus_scheduler[0].arn

  input = jsonencode({
    action           = "start"
    desired_capacity = var.desired_capacity
  })
}

resource "aws_cloudwatch_event_rule" "stop_scanners" {
  count               = var.demo_mode ? 1 : 0
  name                = "${var.project_name}-stop-nessus-scanners"
  description         = "Stop Nessus scanners for demo mode"
  schedule_expression = var.demo_stop_schedule

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "stop_scanners" {
  count = var.demo_mode ? 1 : 0
  rule  = aws_cloudwatch_event_rule.stop_scanners[0].name
  arn   = aws_lambda_function.nessus_scheduler[0].arn

  input = jsonencode({
    action           = "stop"
    desired_capacity = 0
  })
}

resource "aws_lambda_permission" "allow_eventbridge_start" {
  count         = var.demo_mode ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nessus_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_scanners[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge_stop" {
  count         = var.demo_mode ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeStop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.nessus_scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_scanners[0].arn
}

# SNS topic for alerts
resource "aws_sns_topic" "nessus_alerts" {
  name = "${var.project_name}-nessus-alerts"

  tags = var.common_tags
}

resource "aws_sns_topic_subscription" "nessus_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.nessus_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
