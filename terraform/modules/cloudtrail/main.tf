# CloudTrail Module for Enterprise API Logging and Auditing

# S3 Bucket for CloudTrail Logs
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-${random_id.cloudtrail_suffix.hex}"
  force_destroy = var.force_destroy_cloudtrail_bucket

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-cloudtrail-bucket"
    Type    = "s3-bucket"
    Purpose = "cloudtrail-logging"
  })
}

resource "random_id" "cloudtrail_suffix" {
  byte_length = 4
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.s3_kms_key_id
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 Bucket Policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-cloudtrail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-cloudtrail"
          }
        }
      }
    ]
  })
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.cloudwatch_kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cloudtrail-logs"
    Type = "cloudwatch-log-group"
  })
}

# IAM Role for CloudTrail to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# IAM Policy for CloudTrail to CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# CloudTrail
resource "aws_cloudtrail" "main" {
  name           = "${var.project_name}-cloudtrail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.bucket
  s3_key_prefix  = "cloudtrail"

  # CloudWatch Logs integration
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # Configuration
  include_global_service_events = var.include_global_service_events
  is_multi_region_trail         = var.is_multi_region_trail
  enable_logging                = true
  enable_log_file_validation    = true
  kms_key_id                    = var.cloudtrail_kms_key_id

  # Event selectors for data events
  dynamic "event_selector" {
    for_each = var.enable_data_events ? [1] : []
    content {
      read_write_type                  = "All"
      include_management_events        = true
      exclude_management_event_sources = var.exclude_management_event_sources

      # S3 data events
      data_resource {
        type   = "AWS::S3::Object"
        values = ["arn:aws:s3:::*/*"]
      }

      # Lambda data events
      data_resource {
        type   = "AWS::Lambda::Function"
        values = ["arn:aws:lambda:*"]
      }
    }
  }

  # Insight selectors for API call analytics
  dynamic "insight_selector" {
    for_each = var.enable_insights ? [1] : []
    content {
      insight_type = "ApiCallRateInsight"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cloudtrail"
    Type = "cloudtrail"
  })

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# SNS Topic for CloudTrail Notifications
resource "aws_sns_topic" "cloudtrail_notifications" {
  name         = "${var.project_name}-cloudtrail-notifications"
  display_name = "CloudTrail Security Notifications"

  kms_master_key_id = var.sns_kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-cloudtrail-notifications"
    Type = "sns-topic"
  })
}

# CloudWatch Metric Filters for Security Events
resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "${var.project_name}-root-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootUsageEventCount"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "unauthorized_calls" {
  name           = "${var.project_name}-unauthorized-calls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedOperation\") || ($.errorCode = \"AccessDenied*\") }"

  metric_transformation {
    name      = "UnauthorizedCallEventCount"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "console_signin_failures" {
  name           = "${var.project_name}-console-signin-failures"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = ConsoleLogin) && ($.responseElements.ConsoleLogin = Failure) }"

  metric_transformation {
    name      = "ConsoleSigninFailureCount"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  name           = "${var.project_name}-iam-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{($.eventName=DeleteGroupPolicy)||($.eventName=DeleteRolePolicy)||($.eventName=DeleteUserPolicy)||($.eventName=PutGroupPolicy)||($.eventName=PutRolePolicy)||($.eventName=PutUserPolicy)||($.eventName=CreateRole)||($.eventName=DeleteRole)||($.eventName=CreatePolicy)||($.eventName=DeletePolicy)||($.eventName=CreateInstanceProfile)||($.eventName=DeleteInstanceProfile)||($.eventName=AddRoleToInstanceProfile)||($.eventName=RemoveRoleFromInstanceProfile)}"

  metric_transformation {
    name      = "IAMChangeEventCount"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}

# CloudWatch Alarms for Security Events
resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${var.project_name}-root-usage-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "RootUsageEventCount"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Root user activity detected"
  alarm_actions       = [aws_sns_topic.cloudtrail_notifications.arn]

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_calls" {
  alarm_name          = "${var.project_name}-unauthorized-calls-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedCallEventCount"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "High number of unauthorized API calls"
  alarm_actions       = [aws_sns_topic.cloudtrail_notifications.arn]

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  alarm_name          = "${var.project_name}-iam-changes-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "IAMChangeEventCount"
  namespace           = "CloudTrailMetrics"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "IAM configuration changes detected"
  alarm_actions       = [aws_sns_topic.cloudtrail_notifications.arn]

  tags = var.common_tags
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
