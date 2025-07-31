# Terraform Variables - Cleaned of unused variables
# Only variables actually used in main.tf and modules

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "optum"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod, demo)"
  type        = string
  default     = "demo"
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

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "optum-demo-user"
}

variable "primary_region" {
  description = "Primary AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "enabled_regions" {
  description = "List of AWS regions to deploy to (used for full/production mode)"
  type        = list(string)
  default     = ["eu-west-1", "us-east-1", "us-west-2", "ap-southeast-1", "ca-central-1"]
}

variable "domain_name" {
  description = "Domain name for the application (optional)"
  type        = string
  default     = ""
}

variable "create_dns_zone" {
  description = "Whether to create a Route53 hosted zone"
  type        = bool
  default     = false
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["203.45.67.89/32"] # Developer IP for demo environment
}

variable "allowed_web_access_cidrs" {
  description = "List of CIDR blocks allowed for web interface access (ALB, Jenkins, Nessus)"
  type        = list(string)
  default     = ["203.45.67.89/32"] # Developer IP for demo environment
}

variable "allowed_web_cidrs" {
  description = "List of CIDR blocks allowed for web access"
  type        = list(string)
  default     = ["203.45.67.89/32"] # Restricted to developer IP for security
}

variable "iam_path" {
  description = "Path for IAM resources"
  type        = string
  default     = "/"
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_security_enhancements" {
  description = "Enable all 4 security enhancements (GuardDuty, Config, WAF, Enhanced SGs)"
  type        = bool
  default     = false
}

variable "use_enhanced_security_groups" {
  description = "Use enhanced security groups with stricter rules"
  type        = bool
  default     = false
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for EC2 instances"
  type        = string
  default     = "optum-demo-key" # Change this to your key pair name
}

variable "nessus_activation_code" {
  description = "Nessus Essentials activation code (free tier, max 16 IPs)"
  type        = string
  default     = ""
  sensitive   = true
}

# Complex object variables for instance configurations
variable "jenkins_agents" {
  description = "Jenkins agents configuration"
  type = object({
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
  default = {
    min_size         = 1
    max_size         = 3
    desired_capacity = 2
  }
}

variable "nessus_scanners" {
  description = "Nessus scanners configuration"
  type = object({
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
  default = {
    min_size         = 1
    max_size         = 2
    desired_capacity = 1
  }
}

variable "app_servers" {
  description = "Application servers configuration"
  type = object({
    count            = number
    instance_type    = string
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
  default = {
    count            = 2
    instance_type    = "t3.micro"
    min_size         = 1
    max_size         = 2
    desired_capacity = 2
  }
}

# Computed variables from locals.tf
variable "vpc_cidr_blocks" {
  description = "VPC CIDR blocks for each region"
  type        = map(string)
  default = {
    "eu-west-1"      = "10.0.0.0/16"
    "us-east-1"      = "10.1.0.0/16"
    "us-west-2"      = "10.2.0.0/16"
    "ap-southeast-1" = "10.3.0.0/16"
    "ca-central-1"   = "10.4.0.0/16"
  }
}

variable "instance_sizes" {
  description = "Instance sizes based on deployment mode"
  type = object({
    demo = object({
      jenkins_master = string
      jenkins_agent  = string
      nessus         = string
      app_server     = string
      bastion        = string
    })
    full = object({
      jenkins_master = string
      jenkins_agent  = string
      nessus         = string
      app_server     = string
      bastion        = string
    })
  })
  default = {
    demo = {
      jenkins_master = "t3.medium"
      jenkins_agent  = "t3.small"
      nessus         = "t3.medium"
      app_server     = "t3.micro"
      bastion        = "t3.micro"
    }
    full = {
      jenkins_master = "t3.large"
      jenkins_agent  = "t3.medium"
      nessus         = "t3.large"
      app_server     = "t3.small"
      bastion        = "t3.small"
    }
  }
}

variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = false
}

variable "enable_vpn" {
  description = "Enable Client VPN"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "Additional allowed CIDR blocks"
  type        = list(string)
  default     = []
}

# Security enhancement variables for CloudTrail and Patch Management
variable "cloudwatch_log_group_retention" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 90
}

variable "enable_log_file_validation" {
  description = "Enable CloudTrail log file validation"
  type        = bool
  default     = true
}

variable "include_global_service_events" {
  description = "Include global service events in CloudTrail"
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = "Enable multi-region CloudTrail"
  type        = bool
  default     = false
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for security events"
  type        = bool
  default     = true
}

# Additional variables used in deployment scripts
variable "enable_transit_gateway" {
  description = "Enable Transit Gateway for multi-region connectivity"
  type        = bool
  default     = false
}

variable "enable_multi_region" {
  description = "Enable multi-region deployment"
  type        = bool
  default     = false
}

variable "demo_email_address" {
  description = "Email address for demo notifications"
  type        = string
  default     = ""
}

variable "enable_cost_alerts" {
  description = "Enable cost monitoring alerts"
  type        = bool
  default     = true
}

variable "daily_budget_limit" {
  description = "Daily budget limit for cost alerts"
  type        = number
  default     = 50
}

variable "alert_email_addresses" {
  description = "List of email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false
}

variable "enable_vulnerability_testing" {
  description = "Enable vulnerability testing features"
  type        = bool
  default     = false
}

variable "create_intentional_vulns" {
  description = "Create intentional vulnerabilities for demo purposes"
  type        = bool
  default     = false
}

variable "enable_demo_mode" {
  description = "Enable demo mode with limited lifetime"
  type        = bool
  default     = false
}

variable "demo_duration_hours" {
  description = "Duration in hours for demo mode"
  type        = number
  default     = 6
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway for all AZs"
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "Create one NAT Gateway per AZ"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPC"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
