variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "force_destroy_cloudtrail_bucket" {
  description = "Force destroy CloudTrail S3 bucket on deletion"
  type        = bool
  default     = false
}

variable "cloudwatch_log_group_retention" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 90
}

variable "enable_log_file_validation" {
  description = "Enable CloudTrail log file validation"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable CloudTrail logging"
  type        = bool
  default     = true
}

variable "include_global_service_events" {
  description = "Include global service events"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Enable multi-region trail"
  type        = bool
  default     = false
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for security events"
  type        = bool
  default     = true
}

variable "s3_kms_key_id" {
  description = "KMS key ID for S3 encryption"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Log retention days for lifecycle policy"
  type        = number
  default     = 365
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 90
}

variable "cloudwatch_kms_key_id" {
  description = "KMS key ID for CloudWatch encryption"
  type        = string
  default     = null
}

variable "cloudtrail_kms_key_id" {
  description = "KMS key ID for CloudTrail encryption"
  type        = string
  default     = null
}

variable "sns_kms_key_id" {
  description = "KMS key ID for SNS encryption"
  type        = string
  default     = null
}

variable "enable_data_events" {
  description = "Enable data events logging"
  type        = bool
  default     = false
}

variable "enable_insights" {
  description = "Enable CloudTrail Insights"
  type        = bool
  default     = false
}

variable "exclude_management_event_sources" {
  description = "Management event sources to exclude"
  type        = list(string)
  default     = []
}
