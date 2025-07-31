variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
}

variable "vpc_configs" {
  description = "VPC configurations for private hosted zone (optional for public zones)"
  type = map(object({
    vpc_id = string
    region = string
  }))
  default = {}
}

variable "private_zone" {
  description = "Whether to create a private hosted zone"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# ALB configurations are now handled as separate resources to avoid circular dependencies
