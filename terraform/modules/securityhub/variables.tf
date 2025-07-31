# Security Hub Module Variables

variable "enable_security_hub" {
  description = "Enable AWS Security Hub"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty integration with Security Hub"
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "config_role_arn" {
  description = "ARN of the Config service role"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
