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

variable "critical_patch_days" {
  description = "Days to wait before applying critical patches"
  type        = number
  default     = 3
}

variable "medium_patch_days" {
  description = "Days to wait before applying medium priority patches"
  type        = number
  default     = 14
}

variable "enable_maintenance_windows" {
  description = "Enable maintenance windows for patching"
  type        = bool
  default     = true
}

variable "maintenance_window_schedule" {
  description = "Cron schedule for maintenance windows"
  type        = string
  default     = "cron(0 2 ? * SAT *)"
}

variable "approved_patches" {
  description = "List of approved patches"
  type        = list(string)
  default     = []
}

variable "rejected_patches" {
  description = "List of rejected patches"
  type        = list(string)
  default     = []
}

variable "patch_logs_bucket" {
  description = "S3 bucket for patch logs"
  type        = string
  default     = ""
}

variable "sns_kms_key_id" {
  description = "KMS key ID for SNS encryption"
  type        = string
  default     = "alias/aws/sns"
}

variable "enable_cve_tracking" {
  description = "Enable CVE tracking functionality"
  type        = bool
  default     = false
}

variable "inventory_bucket" {
  description = "S3 bucket for inventory collection"
  type        = string
  default     = ""
}
