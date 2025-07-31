variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where bastion will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of public subnet IDs for bastion ASG"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for bastion"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "instance_type" {
  description = "Instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID for bastion host (if not provided, latest Amazon Linux 2 will be used)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "create_eip" {
  description = "Whether to create and associate an Elastic IP"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days"
  type        = number
  default     = 30
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH (used in security group)"
  type        = list(string)
  default     = ["203.45.67.89/32"] # Developer IP for demo environment
}

# IAM configuration from external IAM module
variable "bastion_instance_profile" {
  description = "Name of the bastion instance profile from IAM module"
  type        = string
}

variable "bastion_role_arn" {
  description = "ARN of the bastion IAM role from IAM module"
  type        = string
}
