# Jenkins Module Variables

variable "project" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
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

# Network configuration
variable "vpc_id" {
  description = "VPC ID where Jenkins will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Jenkins instances"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

# Security Groups
variable "alb_security_group_id" {
  description = "Security Group ID of the ALB"
  type        = string
}

# IAM configuration from external IAM module
variable "jenkins_master_instance_profile" {
  description = "Name of the Jenkins master instance profile from IAM module"
  type        = string
}

variable "jenkins_agent_instance_profile" {
  description = "Name of the Jenkins agent instance profile from IAM module"
  type        = string
}

variable "jenkins_master_role_arn" {
  description = "ARN of the Jenkins master IAM role from IAM module"
  type        = string
}

variable "jenkins_agent_role_arn" {
  description = "ARN of the Jenkins agent IAM role from IAM module"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security Group ID of the bastion host"
  type        = string
}

# ALB configuration
variable "alb_target_group_arn" {
  description = "ARN of the ALB target group for Jenkins master"
  type        = string
}

# Instance configuration
variable "ami_id" {
  description = "AMI ID for Jenkins instances"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "instance_sizes" {
  description = "Instance sizes for different deployment modes"
  type = object({
    demo = object({
      jenkins = string
    })
    full = object({
      jenkins = string
    })
  })
  default = {
    demo = {
      jenkins = "t3.large"
    }
    full = {
      jenkins = "t3.medium"
    }
  }
}

# Auto Scaling configuration
variable "agents_config" {
  description = "Auto Scaling configuration for Jenkins agents"
  type = object({
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
  default = {
    min_size         = 1
    max_size         = 5
    desired_capacity = 2
  }
}

# Secrets Manager ARNs
variable "jenkins_secrets_arn" {
  description = "ARN of the Secrets Manager secret containing Jenkins configuration"
  type        = string
}

variable "nessus_webhook_secret_arn" {
  description = "ARN of the Secrets Manager secret containing Nessus webhook credentials"
  type        = string
}

# Storage configuration
variable "artifact_retention_days" {
  description = "Number of days to retain Jenkins artifacts in S3"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
}

# Jenkins configuration
variable "jenkins_admin_user" {
  description = "Jenkins admin username"
  type        = string
  default     = "admin"
}

variable "jenkins_plugins" {
  description = "List of Jenkins plugins to install"
  type        = list(string)
  default = [
    "ant",
    "antisamy-markup-formatter",
    "build-timeout",
    "credentials-binding",
    "timestamper",
    "ws-cleanup",
    "github",
    "github-branch-source",
    "pipeline-github-lib",
    "pipeline-stage-view",
    "git",
    "ssh-slaves",
    "matrix-auth",
    "pam-auth",
    "ldap",
    "email-ext",
    "mailer",
    "slack",
    "ansible",
    "ec2",
    "aws-credentials",
    "s3",
    "pipeline-aws",
    "docker-workflow",
    "blueocean",
    "prometheus",
    "monitoring"
  ]
}

variable "pipeline_configurations" {
  description = "Jenkins pipeline configurations"
  type = object({
    default_branch    = string
    build_timeout     = number
    concurrent_builds = bool
    github_org        = string
    webhook_url       = string
  })
  default = {
    default_branch    = "main"
    build_timeout     = 60
    concurrent_builds = false
    github_org        = "optum-uk"
    webhook_url       = ""
  }
}

# Nessus integration
variable "nessus_integration" {
  description = "Nessus scanner integration configuration"
  type = object({
    enabled        = bool
    webhook_path   = string
    scanner_policy = string
    scan_schedule  = string
  })
  default = {
    enabled        = true
    webhook_path   = "/nessus-webhook"
    scanner_policy = "Basic Network Scan"
    scan_schedule  = "H 2 * * *" # Daily at 2 AM
  }
}

# Cost optimization
variable "enable_spot_instances" {
  description = "Enable spot instances for Jenkins agents (cost optimization)"
  type        = bool
  default     = true
}

variable "spot_instance_types" {
  description = "List of instance types for spot instances"
  type        = list(string)
  default     = ["t3.micro", "t3.small", "t3a.micro", "t3a.small"]
}

# Monitoring configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Feature flags
variable "enable_backup" {
  description = "Enable automated backups of Jenkins configuration"
  type        = bool
  default     = false
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "cron(0 3 * * ? *)" # Daily at 3 AM
}

variable "enable_ssl" {
  description = "Enable SSL termination at Jenkins level (in addition to ALB)"
  type        = bool
  default     = false
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for Jenkins"
  type        = string
  default     = ""
}

# Multi-region configuration
variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for artifacts"
  type        = bool
  default     = false
}

variable "replication_regions" {
  description = "List of regions for artifact replication"
  type        = list(string)
  default     = []
}

# Jenkins Job DSL configuration
variable "seed_jobs" {
  description = "List of seed jobs to create during initialization"
  type = list(object({
    name        = string
    description = string
    repository  = string
    script_path = string
  }))
  default = [
    {
      name        = "infrastructure-provisioning"
      description = "Terraform-based infrastructure provisioning pipeline"
      repository  = "https://github.com/Dwalker0357/Optum_UK_AWS_Demo"
      script_path = "jenkins/seed-jobs/infrastructure.groovy"
    },
    {
      name        = "security-scanning"
      description = "Automated security scanning with Nessus integration"
      repository  = "https://github.com/Dwalker0357/Optum_UK_AWS_Demo"
      script_path = "jenkins/seed-jobs/security.groovy"
    }
  ]
}
