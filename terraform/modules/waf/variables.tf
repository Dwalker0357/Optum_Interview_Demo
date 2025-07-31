# WAF Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region for unique resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_geo_blocking" {
  description = "Enable geographic blocking"
  type        = bool
  default     = false
}

variable "blocked_countries" {
  description = "List of country codes to block"
  type        = list(string)
  default     = []
}

variable "rate_limit" {
  description = "Rate limit for requests per 5 minutes from single IP"
  type        = number
  default     = 2000
}

variable "allowed_ip_addresses" {
  description = "List of IP addresses to whitelist"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain WAF logs"
  type        = number
  default     = 30
}

variable "cloudwatch_kms_key_id" {
  description = "KMS key ID for CloudWatch logs encryption"
  type        = string
  default     = null
}

variable "sns_kms_key_id" {
  description = "KMS key ID for SNS topic encryption"
  type        = string
  default     = null
}

variable "block_threshold" {
  description = "Threshold for blocked requests alarm"
  type        = number
  default     = 100
}
