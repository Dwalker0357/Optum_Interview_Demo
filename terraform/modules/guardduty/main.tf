# GuardDuty Module for Enterprise Threat Detection

# Enable GuardDuty
resource "aws_guardduty_detector" "main" {
  enable                       = true
  finding_publishing_frequency = var.finding_publishing_frequency

  datasources {
    s3_logs {
      enable = var.enable_s3_protection
    }
    kubernetes {
      audit_logs {
        enable = var.enable_kubernetes_protection
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = var.enable_malware_protection
        }
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-guardduty"
    Type = "security-service"
  })
}

# GuardDuty Threat Intel Set
resource "aws_guardduty_threatintelset" "main" {
  count = var.threat_intel_set_location != "" ? 1 : 0

  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = var.threat_intel_set_location
  name        = "${var.project_name}-threat-intel-set"

  tags = var.common_tags
}

# GuardDuty IP Set for trusted IPs
resource "aws_guardduty_ipset" "trusted" {
  count = var.trusted_ip_set_location != "" ? 1 : 0

  activate    = true
  detector_id = aws_guardduty_detector.main.id
  format      = "TXT"
  location    = var.trusted_ip_set_location
  name        = "${var.project_name}-trusted-ips"

  tags = var.common_tags
}

# SNS Topic for GuardDuty Findings
resource "aws_sns_topic" "guardduty_findings" {
  name         = "${var.project_name}-guardduty-findings"
  display_name = "GuardDuty Security Findings"

  kms_master_key_id = var.kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-guardduty-findings"
    Type = "sns-topic"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "guardduty_findings" {
  arn = aws_sns_topic.guardduty_findings.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.guardduty_findings.arn
      }
    ]
  })
}

# EventBridge Rule for High/Medium Severity Findings
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings"
  description = "GuardDuty findings for immediate attention"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [4.0, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9,
        5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9,
        6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8, 6.9,
        7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9,
      8.0, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 8.9]
    }
  })

  tags = var.common_tags
}

# EventBridge Target for SNS
resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyToSNS"
  arn       = aws_sns_topic.guardduty_findings.arn
}

# CloudWatch Log Group for GuardDuty
resource "aws_cloudwatch_log_group" "guardduty" {
  name              = "/aws/guardduty/${var.project_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-guardduty-logs"
    Type = "cloudwatch-log-group"
  })
}

# Lambda Function for Custom Responses (Optional)
resource "aws_lambda_function" "guardduty_response" {
  count = var.enable_auto_response ? 1 : 0

  filename         = "${path.module}/lambda/guardduty_response.zip"
  function_name    = "${var.project_name}-guardduty-response"
  role             = aws_iam_role.lambda_guardduty[0].arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime          = "python3.9"
  timeout          = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.guardduty_findings.arn
      PROJECT_NAME  = var.project_name
    }
  }

  tags = var.common_tags
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_guardduty" {
  count = var.enable_auto_response ? 1 : 0

  name = "${var.project_name}-guardduty-lambda-role"

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

# IAM Policy for Lambda Function
resource "aws_iam_role_policy" "lambda_guardduty" {
  count = var.enable_auto_response ? 1 : 0

  name = "${var.project_name}-guardduty-lambda-policy"
  role = aws_iam_role.lambda_guardduty[0].id

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
        Resource = aws_sns_topic.guardduty_findings.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      }
    ]
  })
}

# Archive Lambda deployment package
data "archive_file" "lambda_zip" {
  count = var.enable_auto_response ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda/guardduty_response.zip"
  source {
    content  = file("${path.module}/lambda/guardduty_response.py")
    filename = "index.py"
  }
}

# EventBridge Target for Lambda
resource "aws_cloudwatch_event_target" "guardduty_lambda" {
  count = var.enable_auto_response ? 1 : 0

  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "GuardDutyToLambda"
  arn       = aws_lambda_function.guardduty_response[0].arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_auto_response ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardduty_response[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}
