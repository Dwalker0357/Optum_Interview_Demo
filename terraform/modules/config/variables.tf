# AWS Config Module Variables

variable "project_name" {
  description = "Name of the project"
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

variable "force_destroy_config_bucket" {
  description = "Force destroy the S3 bucket for Config"
  type        = bool
  default     = false
}

variable "s3_kms_key_id" {
  description = "KMS key ID for S3 bucket encryption"
  type        = string
  default     = null
}

variable "sns_kms_key_id" {
  description = "KMS key ID for SNS topic encryption"
  type        = string
  default     = null
}

variable "include_global_resources" {
  description = "Include global resources in Config recording"
  type        = bool
  default     = true
}

variable "delivery_frequency" {
  description = "Frequency of Config snapshot delivery"
  type        = string
  default     = "TwentyFour_Hours"
  validation {
    condition = contains([
      "One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"
    ], var.delivery_frequency)
    error_message = "Delivery frequency must be a valid value."
  }
}
