# Core Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Nessus will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Nessus deployment"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for Network Load Balancer"
  type        = list(string)
}

variable "internal_lb" {
  description = "Whether to create internal load balancer (true for production, false for testing)"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Networking (Legacy ALB variables - no longer used with NLB)

variable "bastion_security_group_id" {
  description = "Security group ID for the bastion host"
  type        = string

  validation {
    condition     = var.bastion_security_group_id != ""
    error_message = "bastion_security_group_id must not be empty - pass the Bastion SG id from the security module."
  }
}

# Instance Configuration
variable "instance_type" {
  description = "EC2 instance type for Nessus scanners"
  type        = string
  default     = "t3.large"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 50
}

# Auto Scaling Configuration (Nessus Essentials: 1 instance only)
variable "min_capacity" {
  description = "Minimum number of Nessus instances (Essentials: 1)"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of Nessus instances (Essentials: 1)"
  type        = number
  default     = 1
}

variable "desired_capacity" {
  description = "Desired number of Nessus instances (Essentials: 1)"
  type        = number
  default     = 1
}

# Demo Mode Configuration
variable "demo_mode" {
  description = "Enable demo mode with cost optimization features"
  type        = bool
  default     = false
}

variable "demo_start_schedule" {
  description = "Rate expression for starting scanners in demo mode"
  type        = string
  default     = "rate(12 hours)"
}

variable "demo_stop_schedule" {
  description = "Rate expression for stopping scanners in demo mode"
  type        = string
  default     = "rate(24 hours)"
}

# Nessus Essentials Configuration
variable "nessus_activation_code" {
  description = "Nessus Essentials activation code (free tier, max 16 IPs)"
  type        = string
  sensitive   = true
}

variable "nessus_admin_username" {
  description = "Nessus admin username"
  type        = string
  default     = "admin"
}

variable "enable_cve_feed" {
  description = "Enable CVE feed updates"
  type        = bool
  default     = true
}

variable "auto_update_plugins" {
  description = "Enable automatic plugin updates (Essentials: limited)"
  type        = bool
  default     = false
}

# Scanning Configuration
variable "scan_schedule" {
  description = "Default scan schedule (cron format)"
  type        = string
  default     = "0 2 * * *"
}

variable "scan_targets" {
  description = "List of scan targets (CIDR blocks or IP ranges) - Essentials max 16 IPs"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.scan_targets) <= 16
    error_message = "Nessus Essentials supports maximum 16 IP addresses."
  }
}

variable "scan_policies" {
  description = "Map of scan policy configurations"
  type = map(object({
    name        = string
    description = string
    template    = string
    schedule    = string
    targets     = list(string)
  }))
  default = {
    "basic" = {
      name        = "Basic Network Scan"
      description = "Basic vulnerability scan for network discovery"
      template    = "basic"
      schedule    = "0 2 * * 1"
      targets     = []
    }
    "credentialed" = {
      name        = "Essentials Credentialed Scan"
      description = "Limited credentialed vulnerability scan (Essentials)"
      template    = "credentialed"
      schedule    = "0 3 * * 3"
      targets     = []
    }
    "web" = {
      name        = "Web Application Scan"
      description = "Web application vulnerability scan"
      template    = "web"
      schedule    = "0 4 * * 5"
      targets     = []
    }
  }
}

# Integration Configuration
variable "jenkins_webhook_url" {
  description = "Jenkins webhook URL for scan result notifications"
  type        = string
  default     = ""
}

variable "jenkins_api_token" {
  description = "Jenkins API token for webhook authentication"
  type        = string
  default     = ""
  sensitive   = true
}

# Storage Configuration
variable "report_retention_days" {
  description = "Number of days to retain scan reports in S3"
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

# Monitoring and Alerting
variable "alert_email" {
  description = "Email address for alerts and notifications"
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_scan_sources" {
  description = "CIDR blocks allowed to trigger scans"
  type        = list(string)
  default     = []
}

variable "encryption_key_id" {
  description = "KMS key ID for encryption (optional)"
  type        = string
  default     = ""
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Use spot instances for cost optimization"
  type        = bool
  default     = false
}

variable "spot_price" {
  description = "Maximum spot price (if using spot instances)"
  type        = string
  default     = ""
}

# Report Distribution
variable "report_email_recipients" {
  description = "List of email addresses to receive scan reports"
  type        = list(string)
  default     = []
}

variable "report_format" {
  description = "Default report format (html, pdf, csv)"
  type        = string
  default     = "html"
}

variable "enable_executive_summary" {
  description = "Generate executive summary reports"
  type        = bool
  default     = true
}

# Plugin Feed Configuration
variable "plugin_feed_url" {
  description = "Custom plugin feed URL (optional)"
  type        = string
  default     = ""
}

variable "plugin_update_schedule" {
  description = "Schedule for plugin updates (cron format)"
  type        = string
  default     = "0 1 * * *"
}

# Compliance Configuration
variable "compliance_frameworks" {
  description = "List of compliance frameworks to check against"
  type        = list(string)
  default     = ["PCI DSS", "NIST", "CIS"]
}

variable "enable_compliance_reports" {
  description = "Generate compliance reports"
  type        = bool
  default     = true
}

# Advanced Scanning Options
variable "scan_window_start" {
  description = "Start time for scan window (24h format, e.g., '22:00')"
  type        = string
  default     = "22:00"
}

variable "scan_window_end" {
  description = "End time for scan window (24h format, e.g., '06:00')"
  type        = string
  default     = "06:00"
}

variable "max_concurrent_scans" {
  description = "Maximum number of concurrent scans per instance"
  type        = number
  default     = 3
}

variable "scan_timeout_hours" {
  description = "Maximum scan duration in hours"
  type        = number
  default     = 24
}

# Network Scanning Configuration
variable "discovery_scan_range" {
  description = "IP range for network discovery scans"
  type        = string
  default     = ""
}

variable "port_scan_range" {
  description = "Port range for scanning (e.g., '1-1000,3389,5985-5986')"
  type        = string
  default     = "1-65535"
}

variable "enable_service_detection" {
  description = "Enable service detection during scans"
  type        = bool
  default     = true
}

# Performance Tuning
variable "scan_performance_level" {
  description = "Scan performance level (1-5, where 5 is most aggressive)"
  type        = number
  default     = 3

  validation {
    condition     = var.scan_performance_level >= 1 && var.scan_performance_level <= 5
    error_message = "Scan performance level must be between 1 and 5."
  }
}

variable "parallel_hosts_scanning" {
  description = "Number of hosts to scan in parallel"
  type        = number
  default     = 20
}

variable "parallel_checks_per_host" {
  description = "Number of checks to run in parallel per host"
  type        = number
  default     = 5
}

variable "nessus_security_group_id" {
  description = "Enhanced security group ID for Nessus instances (if using enhanced security)"
  type        = string
  default     = ""
}
