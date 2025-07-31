# Drift Detection Module
# Implements minimal drift detection using EventBridge + Lambda + Jenkins
# Note: Auto-apply disabled pending further testing

# EventBridge rule for scheduled drift detection
resource "aws_cloudwatch_event_rule" "drift_detection" {
  count = var.enable_drift_detection ? 1 : 0

  name                = "${var.name_prefix}-drift-detection"
  description         = "Scheduled Terraform drift detection"
  schedule_expression = "rate(6 hours)"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-drift-detection"
    Type = "eventbridge-rule"
  })
}

# Lambda function for drift detection
resource "aws_lambda_function" "drift_detector" {
  count = var.enable_drift_detection ? 1 : 0

  filename         = data.archive_file.drift_detector_zip[0].output_path
  function_name    = "${var.name_prefix}-drift-detector"
  role             = aws_iam_role.drift_detector_role[0].arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.drift_detector_zip[0].output_base64sha256
  runtime          = "python3.9"
  timeout          = 300

  environment {
    variables = {
      JENKINS_URL   = var.jenkins_url
      JENKINS_USER  = var.jenkins_user
      JENKINS_TOKEN = var.jenkins_token
      S3_BUCKET     = var.state_bucket
      SNS_TOPIC_ARN = aws_sns_topic.drift_alerts[0].arn
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-drift-detector"
    Type = "lambda-function"
  })
}

# Lambda code archive
data "archive_file" "drift_detector_zip" {
  count = var.enable_drift_detection ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/drift_detector.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      jenkins_url  = var.jenkins_url
      jenkins_user = var.jenkins_user
      state_bucket = var.state_bucket
    })
    filename = "lambda_function.py"
  }
}

# EventBridge target for Lambda
resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_drift_detection ? 1 : 0

  rule      = aws_cloudwatch_event_rule.drift_detection[0].name
  target_id = "TriggerDriftDetection"
  arn       = aws_lambda_function.drift_detector[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_drift_detection ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drift_detector[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.drift_detection[0].arn
}

# IAM role for Lambda
resource "aws_iam_role" "drift_detector_role" {
  count = var.enable_drift_detection ? 1 : 0

  name = "${var.name_prefix}-drift-detector-role"

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

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-drift-detector-role"
    Type = "iam-role"
  })
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "drift_detector_policy" {
  count = var.enable_drift_detection ? 1 : 0

  name = "${var.name_prefix}-drift-detector-policy"
  role = aws_iam_role.drift_detector_role[0].id

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
          "s3:ListBucket",
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.state_bucket}",
          "arn:aws:s3:::${var.state_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.drift_alerts[0].arn
      }
    ]
  })
}

# SNS topic for drift alerts
resource "aws_sns_topic" "drift_alerts" {
  count = var.enable_drift_detection ? 1 : 0

  name = "${var.name_prefix}-drift-alerts"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-drift-alerts"
    Type = "sns-topic"
  })
}

# S3 bucket for drift detection reports
resource "aws_s3_bucket" "drift_reports" {
  count = var.enable_drift_detection ? 1 : 0

  bucket = "${var.name_prefix}-drift-reports-${random_string.bucket_suffix[0].result}"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-drift-reports"
    Type = "s3-bucket"
  })
}

resource "random_string" "bucket_suffix" {
  count = var.enable_drift_detection ? 1 : 0

  length  = 8
  special = false
  upper   = false
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "drift_reports" {
  count = var.enable_drift_detection ? 1 : 0

  bucket = aws_s3_bucket.drift_reports[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "drift_reports" {
  count = var.enable_drift_detection ? 1 : 0

  bucket = aws_s3_bucket.drift_reports[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
