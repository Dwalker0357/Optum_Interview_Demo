# Drift Detection Module Variables

variable "enable_drift_detection" {
  description = "Enable automated drift detection"
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "jenkins_url" {
  description = "Jenkins URL for triggering drift detection jobs"
  type        = string
  default     = ""
}

variable "jenkins_user" {
  description = "Jenkins username for API access"
  type        = string
  default     = ""
}

variable "jenkins_token" {
  description = "Jenkins API token for authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
