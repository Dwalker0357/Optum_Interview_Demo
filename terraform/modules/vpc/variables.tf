# VPC Module Variables

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = []
}

variable "num_azs" {
  description = "Number of Availability Zones to use"
  type        = number
  default     = 2
  validation {
    condition     = var.num_azs >= 1 && var.num_azs <= 6
    error_message = "Number of AZs must be between 1 and 6."
  }
}

variable "deployment_mode" {
  description = "Deployment mode: demo or full"
  type        = string
  default     = "demo"
  validation {
    condition     = contains(["demo", "full"], var.deployment_mode)
    error_message = "Deployment mode must be either 'demo' or 'full'."
  }
}

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways for each of your private networks"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Should be true to provision a single shared NAT Gateway across all of your private networks"
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "Should be true to provision one NAT Gateway per AZ"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Should be true to enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Should be true to enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention period for VPC Flow Logs"
  type        = number
  default     = 30
}

variable "enable_vpc_endpoints" {
  description = "Whether to create VPC endpoints"
  type        = bool
  default     = true
}

variable "vpc_endpoints_services" {
  description = "List of AWS services for VPC endpoints"
  type        = list(string)
  default     = ["ec2", "secretsmanager"]

  validation {
    condition     = length(var.vpc_endpoints_services) <= 10
    error_message = "Maximum of 10 VPC endpoints allowed to prevent hitting AWS limits."
  }
}

variable "enable_client_vpn" {
  description = "Whether to create Client VPN endpoint"
  type        = bool
  default     = false
}

variable "client_vpn_cidr" {
  description = "CIDR block for Client VPN"
  type        = string
  default     = "172.16.0.0/22"
}

variable "client_vpn_server_certificate_arn" {
  description = "ARN of the server certificate for Client VPN"
  type        = string
  default     = ""
}

variable "client_vpn_client_certificate_arn" {
  description = "ARN of the client certificate for Client VPN"
  type        = string
  default     = ""
}

variable "enable_network_acls" {
  description = "Whether to create custom Network ACLs"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to the resource"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "optum-demo"
}
