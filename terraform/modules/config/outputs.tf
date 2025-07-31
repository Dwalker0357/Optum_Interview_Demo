# AWS Config Module Outputs

output "config_bucket_name" {
  description = "Name of the S3 bucket for Config"
  value       = aws_s3_bucket.config.bucket
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket for Config"
  value       = aws_s3_bucket.config.arn
}

output "configuration_recorder_name" {
  description = "Name of the Config configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "delivery_channel_name" {
  description = "Name of the Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Config notifications"
  value       = aws_sns_topic.config_notifications.arn
}

output "config_role_arn" {
  description = "ARN of the IAM role for Config"
  value       = aws_iam_role.config.arn
}
