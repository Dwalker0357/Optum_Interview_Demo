# Time resource to create stable timestamp for tagging
resource "time_static" "deployment" {}

# Local values for resource naming and configuration
locals {
  # Deployment regions based on mode
  deployment_regions = var.deployment_mode == "demo" ? [var.primary_region] : var.enabled_regions

  # Instance types based on deployment mode
  instance_types = var.instance_sizes[var.deployment_mode]

  # Common resource naming
  name_prefix = "${var.project_name}-${var.environment}"

  # Stable created date from time resource
  created_date = formatdate("YYYY-MM-DD", time_static.deployment.rfc3339)

  # Common tags applied to all resources
  common_tags = {
    Project           = var.project_name
    Environment       = var.environment
    Owner             = var.owner
    DeploymentMode    = var.deployment_mode
    ManagedBy         = "terraform"
    CreatedDate       = local.created_date
    CostCenter        = "DevOps-Interview"
    SecurityLevel     = "Internal"
    BackupRequired    = var.enable_backup ? "true" : "false"
    MonitoringEnabled = var.enable_monitoring ? "true" : "false"
  }

  # Regional configurations
  regional_configs = {
    for region in local.deployment_regions : region => {
      vpc_cidr   = var.vpc_cidr_blocks[region]
      az_count   = 2 # Consistent 2 AZs for 2 private + 1 public subnet requirement
      enable_nat = true
      enable_vpn = var.enable_vpn && region == var.primary_region # VPN only in primary region
    }
  }

  # Security group configurations
  security_groups = {
    bastion = {
      name        = "${local.name_prefix}-bastion-sg"
      description = "Security group for bastion hosts"
      ingress = [
        {
          from_port   = 22
          to_port     = 22
          protocol    = "tcp"
          cidr_blocks = var.allowed_cidr_blocks
          description = "SSH access"
        }
      ]
    }

    jenkins = {
      name        = "${local.name_prefix}-jenkins-sg"
      description = "Security group for Jenkins instances"
      ingress = [
        {
          from_port   = 8080
          to_port     = 8080
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "Jenkins web interface"
        },
        {
          from_port   = 50000
          to_port     = 50000
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "Jenkins agent communication"
        }
      ]
    }

    nessus = {
      name        = "${local.name_prefix}-nessus-sg"
      description = "Security group for Nessus scanners"
      ingress = [
        {
          from_port   = 8834
          to_port     = 8834
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "Nessus web interface"
        }
      ]
    }

    app = {
      name        = "${local.name_prefix}-app-sg"
      description = "Security group for application servers"
      ingress = [
        {
          from_port   = 80
          to_port     = 80
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "HTTP traffic"
        },
        {
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "HTTPS traffic"
        }
      ]
    }

    alb = {
      name        = "${local.name_prefix}-alb-sg"
      description = "Security group for Application Load Balancer"
      ingress = [
        {
          from_port   = 80
          to_port     = 80
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "HTTP traffic"
        },
        {
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = [] # Will be populated with VPC CIDRs
          description = "HTTPS traffic"
        }
      ]
    }
  }

  # Secrets Manager secret names
  secrets = {
    jenkins_admin_password = "${local.name_prefix}/jenkins/admin-password"
    nessus_admin_password  = "${local.name_prefix}/nessus/admin-password"
    vpn_shared_key         = "${local.name_prefix}/vpn/shared-key"
    ssh_private_key        = "${local.name_prefix}/ssh/private-key"
    api_keys               = "${local.name_prefix}/api/keys"
  }

  # Cost optimization settings
  cost_optimization = {
    demo = {
      use_spot_instances         = true
      auto_stop_schedule         = "cron(0 18 ? * MON-FRI *)" # Stop at 6 PM weekdays
      auto_start_schedule        = "cron(0 8 ? * MON-FRI *)"  # Start at 8 AM weekdays
      enable_detailed_monitoring = false
      backup_retention_days      = 7
    }
    full = {
      use_spot_instances         = false
      auto_stop_schedule         = null
      auto_start_schedule        = null
      enable_detailed_monitoring = true
      backup_retention_days      = 30
    }
  }

  # Jenkins pipeline configurations
  jenkins_pipelines = [
    {
      name        = "Deploy-EC2-Instance"
      description = "Deploy EC2 instances with Ansible"
      parameters = [
        { name = "os_type", type = "choice", choices = ["amazon-linux", "ubuntu", "rhel"] },
        { name = "instance_size", type = "choice", choices = ["t3.micro", "t3.small", "t3.medium"] },
        { name = "region", type = "choice", choices = local.deployment_regions },
        { name = "vpc_id", type = "string", description = "Target VPC ID" },
        { name = "subnet_id", type = "string", description = "Target subnet ID" }
      ]
    },
    {
      name        = "Security-Scan-And-Patch"
      description = "Run Nessus scan and apply patches"
      parameters = [
        { name = "target_hosts", type = "string", description = "Comma-separated list of IPs" },
        { name = "patch_level", type = "choice", choices = ["critical", "high", "medium", "all"] },
        { name = "reboot_required", type = "boolean", default = false }
      ]
    }
  ]
}
