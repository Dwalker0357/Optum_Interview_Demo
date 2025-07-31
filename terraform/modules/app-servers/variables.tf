variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where app servers will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for app servers"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for app servers"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN for app servers"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "instance_type" {
  description = "Instance type for app servers"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "AMI ID for app servers (if not provided, latest Amazon Linux 2 will be used)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "min_size" {
  description = "Minimum number of app servers"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of app servers"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of app servers"
  type        = number
  default     = 2
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 30
}

variable "create_vulnerable_s3" {
  description = "Create S3 bucket with intentional vulnerabilities for testing"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# IAM configuration from external IAM module
variable "app_server_instance_profile" {
  description = "Name of the app server instance profile from IAM module"
  type        = string
}

variable "app_server_role_arn" {
  description = "ARN of the app server IAM role from IAM module"
  type        = string
}

variable "vulnerability_types" {
  description = "List of vulnerability types to enable"
  type        = list(string)
  default = [
    "sql_injection",
    "xss",
    "weak_authentication",
    "information_disclosure",
    "insecure_protocols"
  ]
}

variable "enable_vulnerability_scanning" {
  description = "Enable automatic vulnerability scanning alerts"
  type        = bool
  default     = true
}
