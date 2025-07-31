# AWS WAF v2 Module for Application Load Balancer Protection

# WAF Web ACL for ALB
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-${var.region}-${var.environment}-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: AWS Managed Core Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Known Bad Inputs Rule Set
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-BadInputsRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: SQL Database Rule Set
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-SQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Linux Operating System Rule Set
  rule {
    name     = "AWSManagedRulesLinuxRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-LinuxRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Geographic Restriction (Optional)
  dynamic "rule" {
    for_each = var.enable_geo_blocking ? [1] : []
    content {
      name     = "GeoBlockingRule"
      priority = 5

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-GeoBlockingMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rule 6: Rate Limiting
  rule {
    name     = "RateLimitRule"
    priority = 6

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-RateLimitMetric"
      sampled_requests_enabled   = true
    }
  }

  # Rule 7: IP Whitelist (Allow specific IPs to bypass rules)
  dynamic "rule" {
    for_each = length(var.allowed_ip_addresses) > 0 ? [1] : []
    content {
      name     = "IPWhitelistRule"
      priority = 0 # Highest priority

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowed_ips[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-IPWhitelistMetric"
        sampled_requests_enabled   = true
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-web-acl"
    Type = "waf-web-acl"
  })

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-WebACL"
    sampled_requests_enabled   = true
  }
}

# IP Set for Allowed IPs
resource "aws_wafv2_ip_set" "allowed_ips" {
  count = length(var.allowed_ip_addresses) > 0 ? 1 : 0

  name               = "${var.project_name}-${var.region}-${var.environment}-allowed-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ip_addresses

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-allowed-ips"
    Type = "waf-ip-set"
  })
}

# CloudWatch Log Group for WAF (must start with aws-waf-logs- and no leading slash)
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.project_name}-${var.region}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-waf-logs"
    Type = "cloudwatch-log-group"
  })
}

# WAF Logging Configuration
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

# SNS Topic for WAF Alerts
resource "aws_sns_topic" "waf_alerts" {
  name         = "${var.project_name}-waf-alerts"
  display_name = "WAF Security Alerts"

  kms_master_key_id = var.sns_kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-waf-alerts"
    Type = "sns-topic"
  })
}

# CloudWatch Metric Alarm for High Block Rate - commented out to avoid cycle, will be added later
# resource "aws_cloudwatch_metric_alarm" "high_block_rate" {
#   alarm_name          = "${var.project_name}-waf-high-block-rate"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = "2"
#   metric_name         = "BlockedRequests"
#   namespace           = "AWS/WAFV2"
#   period              = "300"
#   statistic           = "Sum"
#   threshold           = var.block_threshold
#   alarm_description   = "This metric monitors high WAF block rate"
#   alarm_actions       = [aws_sns_topic.waf_alerts.arn]

#   dimensions = {
#     WebACL = aws_wafv2_web_acl.main.name
#     Region = data.aws_region.current.name
#   }

#   tags = var.common_tags
# }

# Data sources
data "aws_region" "current" {}
