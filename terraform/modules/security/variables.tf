variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}



variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to bastion"
  type        = list(string)
  default     = ["203.45.67.89/32"] # Developer IP for demo environment
}

variable "allowed_web_cidrs" {
  description = "CIDR blocks allowed to access ALB web interface"
  type        = list(string)
  default     = ["203.45.67.89/32"] # Developer IP for demo environment
}

variable "enable_nessus_scanning" {
  description = "Enable broad port access for Nessus scanning"
  type        = bool
  default     = true
}
