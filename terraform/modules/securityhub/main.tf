# Security Hub Configuration
# Note: This module was implemented as lower priority - limited testing performed

# Enable Security Hub
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0

  enable_default_standards = true

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-security-hub"
    Type = "security-hub"
  })
}

# Enable AWS Config (required for Security Hub)
resource "aws_config_configuration_recorder" "main" {
  count = var.enable_security_hub ? 1 : 0

  name     = "${var.name_prefix}-config-recorder"
  role_arn = var.config_role_arn

  recording_group {
    all_supported = true
  }

  depends_on = [aws_securityhub_account.main]
}

# Enable GuardDuty findings to Security Hub
resource "aws_securityhub_product_subscription" "guardduty" {
  count = var.enable_security_hub && var.enable_guardduty ? 1 : 0

  product_arn = "arn:aws:securityhub:${var.region}::product/aws/guardduty"

  depends_on = [aws_securityhub_account.main]
}

# Security Hub Standards Subscriptions
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.region}::standard/aws-foundational-security"

  depends_on = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count = var.enable_security_hub ? 1 : 0

  standards_arn = "arn:aws:securityhub:${var.region}::standard/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_account.main]
}

# CloudWatch Dashboard for Security Hub
resource "aws_cloudwatch_dashboard" "security_hub" {
  count = var.enable_security_hub ? 1 : 0

  dashboard_name = "${var.name_prefix}-security-hub-dashboard"

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
            ["AWS/SecurityHub", "Findings", "ComplianceType", "PASSED"],
            ["...", "FAILED"],
            ["...", "WARNING"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Security Hub Compliance Status"
          period  = 300
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-security-hub-dashboard"
    Type = "cloudwatch-dashboard"
  })
}

# SNS Topic for Security Hub alerts
resource "aws_sns_topic" "security_hub_alerts" {
  count = var.enable_security_hub ? 1 : 0

  name = "${var.name_prefix}-security-hub-alerts"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-security-hub-alerts"
    Type = "sns-topic"
  })
}

# EventBridge rule for high severity findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  count = var.enable_security_hub ? 1 : 0

  name        = "${var.name_prefix}-security-hub-findings"
  description = "Capture high severity Security Hub findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
      }
    }
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-security-hub-findings"
    Type = "eventbridge-rule"
  })
}

# EventBridge target to SNS
resource "aws_cloudwatch_event_target" "sns" {
  count = var.enable_security_hub ? 1 : 0

  rule      = aws_cloudwatch_event_rule.security_hub_findings[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_hub_alerts[0].arn
}
