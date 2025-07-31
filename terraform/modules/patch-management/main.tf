# Patch Management Module for Enterprise CVE Management

# Systems Manager Patch Baseline for Critical and Security Updates
resource "aws_ssm_patch_baseline" "enterprise" {
  name             = "${var.project_name}-enterprise-baseline"
  description      = "Enterprise patch baseline for critical and security updates"
  operating_system = "AMAZON_LINUX_2"

  # Critical and Security patches within 7 days
  approval_rule {
    approve_after_days  = 0
    compliance_level    = "CRITICAL"
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Critical"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  # Medium priority patches within 30 days
  approval_rule {
    approve_after_days  = 30
    compliance_level    = "MEDIUM"
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Medium"]
    }
  }

  # Approved patches
  approved_patches = var.approved_patches

  # Rejected patches (if any specific patches need to be blocked)
  rejected_patches = var.rejected_patches

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-patch-baseline"
    Type = "ssm-patch-baseline"
  })
}

# Patch Group for Production Systems
resource "aws_ssm_patch_group" "production" {
  baseline_id = aws_ssm_patch_baseline.enterprise.id
  patch_group = "${var.project_name}-production"
}

# Patch Group for Development Systems
resource "aws_ssm_patch_group" "development" {
  baseline_id = aws_ssm_patch_baseline.enterprise.id
  patch_group = "${var.project_name}-development"
}

# Maintenance Window for Production (Weekend)
resource "aws_ssm_maintenance_window" "production" {
  name                       = "${var.project_name}-production-maintenance"
  description                = "Production systems maintenance window"
  schedule                   = "cron(0 2 ? * SUN *)" # 2 AM UTC on Sundays
  duration                   = 4                     # 4 hours
  cutoff                     = 1                     # Stop 1 hour before end
  allow_unassociated_targets = false

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-production-maintenance"
    Type        = "ssm-maintenance-window"
    Environment = "production"
  })
}

# Maintenance Window for Development (Daily)
resource "aws_ssm_maintenance_window" "development" {
  name                       = "${var.project_name}-development-maintenance"
  description                = "Development systems maintenance window"
  schedule                   = "cron(0 3 * * ? *)" # 3 AM UTC daily
  duration                   = 2                   # 2 hours
  cutoff                     = 1                   # Stop 1 hour before end
  allow_unassociated_targets = false

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-development-maintenance"
    Type        = "ssm-maintenance-window"
    Environment = "development"
  })
}

# Maintenance Window Target for Production
resource "aws_ssm_maintenance_window_target" "production" {
  window_id     = aws_ssm_maintenance_window.production.id
  name          = "${var.project_name}-production-targets"
  description   = "Production EC2 instances"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${var.project_name}-production"]
  }

  targets {
    key    = "tag:Environment"
    values = ["production", "prod"]
  }
}

# Maintenance Window Target for Development
resource "aws_ssm_maintenance_window_target" "development" {
  window_id     = aws_ssm_maintenance_window.development.id
  name          = "${var.project_name}-development-targets"
  description   = "Development EC2 instances"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${var.project_name}-development"]
  }

  targets {
    key    = "tag:Environment"
    values = ["development", "dev", "demo"]
  }
}

# Patch Installation Task for Production
resource "aws_ssm_maintenance_window_task" "install_patches_production" {
  max_concurrency = "50%"
  max_errors      = "10%"
  priority        = 1
  task_arn        = "AWS-RunPatchBaseline"
  task_type       = "RUN_COMMAND"
  window_id       = aws_ssm_maintenance_window.production.id
  name            = "${var.project_name}-install-patches-production"
  description     = "Install patches on production instances"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.production.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment         = "Install security and critical patches"
      timeout_seconds = 3600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# Patch Installation Task for Development
resource "aws_ssm_maintenance_window_task" "install_patches_development" {
  max_concurrency = "100%"
  max_errors      = "25%"
  priority        = 1
  task_arn        = "AWS-RunPatchBaseline"
  task_type       = "RUN_COMMAND"
  window_id       = aws_ssm_maintenance_window.development.id
  name            = "${var.project_name}-install-patches-development"
  description     = "Install patches on development instances"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.development.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment              = "Install security and critical patches"
      output_s3_bucket     = var.patch_logs_bucket
      output_s3_key_prefix = "development/patch-logs"
      timeout_seconds      = 3600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

# SNS Topic for Patch Management Notifications
resource "aws_sns_topic" "patch_notifications" {
  name         = "${var.project_name}-patch-notifications"
  display_name = "Patch Management Notifications"

  kms_master_key_id = var.sns_kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-patch-notifications"
    Type = "sns-topic"
  })
}

# CloudWatch Event Rule for Patch Compliance
resource "aws_cloudwatch_event_rule" "patch_compliance" {
  name        = "${var.project_name}-patch-compliance"
  description = "Monitor patch compliance status"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["EC2 Compliance Item State Change"]
    detail = {
      compliance-type   = ["Patch"]
      compliance-status = ["NON_COMPLIANT"]
    }
  })

  tags = var.common_tags
}

# CloudWatch Event Target for SNS
resource "aws_cloudwatch_event_target" "patch_compliance_sns" {
  rule      = aws_cloudwatch_event_rule.patch_compliance.name
  target_id = "PatchComplianceToSNS"
  arn       = aws_sns_topic.patch_notifications.arn
}

# Lambda Function for CVE Tracking
resource "aws_lambda_function" "cve_tracker" {
  count = var.enable_cve_tracking ? 1 : 0

  filename         = "${path.module}/lambda/cve_tracker.zip"
  function_name    = "${var.project_name}-cve-tracker"
  role             = aws_iam_role.cve_tracker_lambda[0].arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.cve_tracker_zip[0].output_base64sha256
  runtime          = "python3.9"
  timeout          = 300

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.patch_notifications.arn
      PROJECT_NAME  = var.project_name
      CVE_API_URL   = "https://services.nvd.nist.gov/rest/json/cves/1.0/"
    }
  }

  tags = var.common_tags
}

# IAM Role for CVE Tracker Lambda
resource "aws_iam_role" "cve_tracker_lambda" {
  count = var.enable_cve_tracking ? 1 : 0

  name = "${var.project_name}-cve-tracker-lambda-role"

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

# IAM Policy for CVE Tracker Lambda
resource "aws_iam_role_policy" "cve_tracker_lambda" {
  count = var.enable_cve_tracking ? 1 : 0

  name = "${var.project_name}-cve-tracker-lambda-policy"
  role = aws_iam_role.cve_tracker_lambda[0].id

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
          "sns:Publish"
        ]
        Resource = aws_sns_topic.patch_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstancePatchStates",
          "ssm:DescribeInstancePatches",
          "ssm:GetPatchBaseline",
          "ssm:DescribePatchBaselines"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge Rule to trigger CVE tracking daily
resource "aws_cloudwatch_event_rule" "cve_tracking_schedule" {
  count = var.enable_cve_tracking ? 1 : 0

  name                = "${var.project_name}-cve-tracking-schedule"
  description         = "Trigger CVE tracking lambda daily"
  schedule_expression = "rate(1 day)"

  tags = var.common_tags
}

# EventBridge Target for CVE Tracking Lambda
resource "aws_cloudwatch_event_target" "cve_tracking_lambda" {
  count = var.enable_cve_tracking ? 1 : 0

  rule      = aws_cloudwatch_event_rule.cve_tracking_schedule[0].name
  target_id = "CVETrackingLambda"
  arn       = aws_lambda_function.cve_tracker[0].arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_cve" {
  count = var.enable_cve_tracking ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cve_tracker[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cve_tracking_schedule[0].arn
}

# Archive CVE Tracker deployment package
data "archive_file" "cve_tracker_zip" {
  count = var.enable_cve_tracking ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda/cve_tracker.zip"
  source {
    content  = file("${path.module}/lambda/cve_tracker.py")
    filename = "index.py"
  }
}

# Systems Manager Association for Inventory Collection
resource "aws_ssm_association" "inventory_collection" {
  name = "AWS-GatherSoftwareInventory"

  targets {
    key    = "tag:Environment"
    values = ["production", "development", "demo"]
  }

  schedule_expression = "rate(1 day)"

  parameters = {
    applications                = "Enabled"
    awsComponents               = "Enabled"
    customInventory             = "Enabled"
    instanceDetailedInformation = "Enabled"
    networkConfig               = "Enabled"
    services                    = "Enabled"
    windowsRoles                = "Enabled"
    windowsUpdates              = "Enabled"
  }

  compliance_severity = "MEDIUM"

  dynamic "output_location" {
    for_each = var.inventory_bucket != "" ? [1] : []
    content {
      s3_bucket_name = var.inventory_bucket
      s3_key_prefix  = "inventory"
    }
  }
}
