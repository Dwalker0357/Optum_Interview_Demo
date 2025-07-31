variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ALB"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "internal" {
  description = "Whether ALB is internal or internet-facing"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for SSL certificate (optional)"
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Enable access logs for ALB"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "jenkins_instance_id" {
  description = "Jenkins instance ID for target group attachment"
  type        = string
  default     = ""
}

# nessus_target_group_arn variable removed - using Network Load Balancer instead

variable "app_server_instance_ids" {
  description = "List of app server instance IDs for target group attachment"
  type        = list(string)
  default     = []
}

variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN to associate with ALB (optional for security enhancement)"
  type        = string
  default     = null
}

variable "enable_waf_association" {
  description = "Enable WAF association with ALB"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for certificate validation"
  type        = string
  default     = ""
}

variable "zone_id" {
  description = "Route53 hosted zone ID for DNS validation (alias for route53_zone_id)"
  type        = string
  default     = ""
}
