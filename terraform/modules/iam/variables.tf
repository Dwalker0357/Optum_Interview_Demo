# IAM Module Variables

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "optum-uk-demo"
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default     = {}
}

variable "demo_mode" {
  description = "Enable demo mode with reduced permissions and simplified policies"
  type        = bool
  default     = false
}

variable "enable_cross_account_access" {
  description = "Enable cross-account access roles"
  type        = bool
  default     = false
}

variable "trusted_account_ids" {
  description = "List of trusted AWS account IDs for cross-account access"
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.trusted_account_ids) == 0 || alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Account IDs must be 12-digit numbers."
  }
}

variable "create_service_linked_roles" {
  description = "Create service-linked roles for AWS services"
  type        = bool
  default     = true
}

# Secrets Manager Configuration
variable "secrets_manager_secret_arns" {
  description = "List of Secrets Manager secret ARNs that services can access"
  type        = list(string)
  default     = []
}

variable "secrets_manager_kms_key_id" {
  description = "KMS key ID used for Secrets Manager encryption"
  type        = string
  default     = ""
}

# S3 Configuration
variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs for service access"
  type        = list(string)
  default     = []
}

variable "jenkins_s3_bucket_arn" {
  description = "S3 bucket ARN for Jenkins artifacts and logs"
  type        = string
  default     = ""
}

variable "nessus_s3_bucket_arn" {
  description = "S3 bucket ARN for Nessus scan reports"
  type        = string
  default     = ""
}

# EFS Configuration
variable "efs_file_system_arns" {
  description = "List of EFS file system ARNs for service access"
  type        = list(string)
  default     = []
}

# CloudWatch Configuration
variable "cloudwatch_log_group_arns" {
  description = "List of CloudWatch log group ARNs for logging permissions"
  type        = list(string)
  default     = []
}

# VPC Configuration (for network-related permissions)
variable "vpc_id" {
  description = "VPC ID for network-related permissions"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for network operations"
  type        = list(string)
  default     = []
}

# EC2 Configuration
variable "allowed_instance_types" {
  description = "List of allowed EC2 instance types for Jenkins agents"
  type        = list(string)
  default     = ["t3.micro", "t3.small", "t3.medium", "m5.large"]
}

variable "jenkins_agent_ami_ids" {
  description = "List of allowed AMI IDs for Jenkins agents"
  type        = list(string)
  default     = []
}

# Security Group Configuration
variable "security_group_ids" {
  description = "List of security group IDs that can be used by services"
  type        = list(string)
  default     = []
}

# Systems Manager Configuration
variable "ssm_parameter_arns" {
  description = "List of SSM Parameter Store ARNs for configuration access"
  type        = list(string)
  default     = []
}

# Ansible Configuration
variable "ansible_playbook_s3_bucket" {
  description = "S3 bucket containing Ansible playbooks"
  type        = string
  default     = ""
}

# Monitoring and Alerting
variable "sns_topic_arns" {
  description = "List of SNS topic ARNs for alerting"
  type        = list(string)
  default     = []
}

# Backup Configuration
variable "backup_vault_arns" {
  description = "List of AWS Backup vault ARNs"
  type        = list(string)
  default     = []
}

# Application-specific variables
variable "application_secrets_prefix" {
  description = "Prefix for application-specific secrets in Secrets Manager"
  type        = string
  default     = "app/"
}

variable "jenkins_secrets_prefix" {
  description = "Prefix for Jenkins-specific secrets in Secrets Manager"
  type        = string
  default     = "jenkins/"
}

variable "nessus_secrets_prefix" {
  description = "Prefix for Nessus-specific secrets in Secrets Manager"
  type        = string
  default     = "nessus/"
}

# Session Manager Configuration
variable "enable_session_manager_logging" {
  description = "Enable Session Manager session logging to CloudWatch and S3"
  type        = bool
  default     = true
}

variable "session_manager_log_bucket" {
  description = "S3 bucket for Session Manager logs"
  type        = string
  default     = ""
}

# Resource naming
variable "resource_prefix" {
  description = "Prefix for all IAM resource names"
  type        = string
  default     = ""
}

variable "resource_suffix" {
  description = "Suffix for all IAM resource names"
  type        = string
  default     = ""
}

# Cost optimization
variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for IAM resources"
  type        = bool
  default     = true
}

# Security
variable "require_mfa_for_cross_account" {
  description = "Require MFA for cross-account role assumption"
  type        = bool
  default     = true
}

variable "max_session_duration" {
  description = "Maximum session duration for IAM roles (in seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "Session duration must be between 3600 (1 hour) and 43200 (12 hours) seconds."
  }
}

# Regional restrictions
variable "allowed_regions" {
  description = "List of AWS regions where resources can be created"
  type        = list(string)
  default     = ["eu-west-2", "eu-west-1", "us-east-1"]
}

# Path-based organization
variable "iam_path" {
  description = "IAM path for organizing resources"
  type        = string
  default     = "/"
  validation {
    condition     = can(regex("^/.*/$", var.iam_path)) || var.iam_path == "/"
    error_message = "IAM path must start and end with forward slashes."
  }
}
