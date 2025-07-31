# GuardDuty Module Variables

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

variable "finding_publishing_frequency" {
  description = "Frequency of GuardDuty findings publication"
  type        = string
  default     = "SIX_HOURS"
  validation {
    condition = contains([
      "FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"
    ], var.finding_publishing_frequency)
    error_message = "Finding publishing frequency must be FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS."
  }
}

variable "enable_s3_protection" {
  description = "Enable S3 protection in GuardDuty"
  type        = bool
  default     = true
}

variable "enable_kubernetes_protection" {
  description = "Enable Kubernetes protection in GuardDuty"
  type        = bool
  default     = false
}

variable "enable_malware_protection" {
  description = "Enable malware protection in GuardDuty"
  type        = bool
  default     = true
}

variable "threat_intel_set_location" {
  description = "S3 location of threat intelligence set"
  type        = string
  default     = ""
}

variable "trusted_ip_set_location" {
  description = "S3 location of trusted IP set"
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = "KMS key ID for SNS topic encryption"
  type        = string
  default     = null
}

variable "cloudwatch_kms_key_id" {
  description = "KMS key ID for CloudWatch logs encryption"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Number of days to retain GuardDuty logs"
  type        = number
  default     = 90
}

variable "enable_auto_response" {
  description = "Enable automatic response to GuardDuty findings"
  type        = bool
  default     = false
}
