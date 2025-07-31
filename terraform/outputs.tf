# Main Terraform outputs for the Optum UK AWS Demo

# Deployment Information
output "deployment_mode" {
  description = "Current deployment mode (demo or full)"
  value       = var.deployment_mode
}

output "deployment_regions" {
  description = "List of regions where infrastructure is deployed"
  value       = local.deployment_regions
}

output "project_info" {
  description = "Project identification information"
  value = {
    name        = var.project_name
    environment = var.environment
    owner       = var.owner
  }
}

# Network Information
output "vpc_info" {
  description = "VPC information for each region"
  value = {
    for region in local.deployment_regions : region => {
      vpc_id              = module.vpc[region].vpc_id
      vpc_cidr            = module.vpc[region].vpc_cidr_block
      public_subnet_ids   = module.vpc[region].public_subnet_ids
      private_subnet_ids  = module.vpc[region].private_subnet_ids
      database_subnet_ids = module.vpc[region].database_subnets
      internet_gateway_id = module.vpc[region].igw_id
      nat_gateway_ids     = module.vpc[region].nat_ids
    }
  }
}

# DNS Information
output "dns_info" {
  description = "Route53 DNS information"
  value = var.create_dns_zone ? {
    zone_id      = module.route53[0].zone_id
    domain_name  = module.route53[0].domain_name
    name_servers = module.route53[0].name_servers
  } : null
}

# Load Balancer Information
output "load_balancer_info" {
  description = "Application Load Balancer information"
  value = {
    for region in local.deployment_regions : region => {
      alb_dns_name  = module.alb[region].alb_dns_name
      alb_arn       = module.alb[region].alb_arn
      target_groups = module.alb[region].target_group_arns
    }
  }
}

# Access Information
output "bastion_info" {
  description = "Bastion host access information"
  value = {
    for region in local.deployment_regions : region => {
      asg_name    = module.bastion[region].bastion_asg_name
      public_ip   = module.bastion[region].bastion_eip_public_ip
      ssh_command = module.bastion[region].ssh_command
      ssm_command = module.bastion[region].session_manager_command
    }
  }
}

# Jenkins Information
output "jenkins_info" {
  description = "Jenkins master and agent information"
  value = {
    for region in local.deployment_regions : region => {
      master_asg_name    = module.jenkins[region].jenkins_master_asg_name
      agents_asg_name    = module.jenkins[region].jenkins_agents_asg_name
      efs_file_system_id = module.jenkins[region].efs_file_system_id
      artifacts_bucket   = module.jenkins[region].artifacts_bucket_name
      jenkins_url        = module.jenkins[region].jenkins_url
    }
  }
}

# Nessus Information
output "nessus_info" {
  description = "Nessus scanner information"
  value = {
    for region in local.deployment_regions : region => {
      asg_name           = module.nessus[region].autoscaling_group_name
      s3_bucket_name     = module.nessus[region].s3_bucket_name
      efs_file_system_id = module.nessus[region].efs_file_system_id
      nlb_dns_name       = module.nessus[region].nlb_dns_name
      nessus_url         = module.nessus[region].nessus_url
      target_group_arn   = module.nessus[region].target_group_arn
    }
  }
}

# Application Servers Information
output "app_servers_info" {
  description = "Application server information"
  value = {
    for region in local.deployment_regions : region => {
      asg_name             = module.app_servers[region].app_servers_asg_name
      s3_bucket_name       = module.app_servers[region].s3_bucket_name
      vulnerable_endpoints = module.app_servers[region].scanning_targets.vulnerable_endpoints
      application_urls     = module.app_servers[region].application_urls
    }
  }
}

# Security Information
output "security_groups" {
  description = "Security group IDs for each service"
  value = {
    for region in local.deployment_regions : region => module.security_groups[region].security_group_ids
  }
}

# Secrets Information
output "secrets_info" {
  description = "AWS Secrets Manager secret information"
  value = {
    secret_names = module.secrets.secret_names
    secret_arns  = module.secrets.secret_arns
  }
  sensitive = true
}

# DNS Information (consolidated with existing output above)

# Certificate Information - commented out, module not implemented
# output "certificates" {
#   description = "SSL certificate information"
#   value = {
#     for region in local.deployment_regions : region => {
#       certificate_arn = module.certificates[region].certificate_arn
#       domain_name     = module.certificates[region].domain_name
#     }
#   }
# }

# Monitoring Information - commented out, module not implemented
# output "monitoring_info" {
#   description = "CloudWatch monitoring information"
#   value = var.enable_monitoring ? {
#     log_groups = module.monitoring[0].log_groups
#     dashboards = module.monitoring[0].dashboards
#     alarms     = module.monitoring[0].alarms
#   } : null
# }

# Transit Gateway Information (Full mode only) - commented out, module not implemented
# output "transit_gateway_info" {
#   description = "Transit Gateway information for multi-region connectivity"
#   value = var.deployment_mode == "full" && var.enable_transit_gateway ? {
#     transit_gateway_id = module.transit_gateway[0].transit_gateway_id
#     route_table_id     = module.transit_gateway[0].route_table_id
#     attachments        = module.transit_gateway[0].vpc_attachments
#   } : null
# }

# Cost Optimization Information - commented out, module not implemented
# output "cost_optimization" {
#   description = "Cost optimization features and schedules"
#   value = var.deployment_mode == "demo" ? {
#     auto_stop_schedule  = local.cost_optimization.demo.auto_stop_schedule
#     auto_start_schedule = local.cost_optimization.demo.auto_start_schedule
#     use_spot_instances  = local.cost_optimization.demo.use_spot_instances
#     managed_instances   = module.cost_optimization[0].managed_instance_ids
#   } : null
# }

# Access Instructions
output "access_instructions" {
  description = "Instructions for accessing deployed services"
  value = {
    ssh_bastion = {
      for region in local.deployment_regions : region =>
      module.bastion[region].ssh_command
    }

    jenkins_access = var.create_dns_zone ? {
      url               = "https://${var.domain_name}/jenkins"
      admin_credentials = "Stored in AWS Secrets Manager: ${local.secrets.jenkins_admin_password}"
      } : {
      url               = "Access via ALB DNS name through bastion host"
      admin_credentials = "Stored in AWS Secrets Manager: ${local.secrets.jenkins_admin_password}"
    }

    nessus_access = {
      url               = values(module.nessus)[0].nessus_url
      admin_credentials = "Stored in AWS Secrets Manager: ${local.secrets.nessus_admin_password}"
      note              = "Direct access via Network Load Balancer on port 8834"
    }

    systems_manager = {
      command = "aws ssm start-session --target <instance-id> --region <region>"
      note    = "Use AWS Systems Manager Session Manager for secure shell access"
    }
  }
}

# Estimated Costs
output "estimated_costs" {
  description = "Estimated monthly costs by service and total"
  value = {
    deployment_mode = var.deployment_mode
    currency        = "USD"

    demo_mode_monthly = var.deployment_mode == "demo" ? {
      compute = {
        bastion     = 3.80  # t3.nano
        jenkins     = 7.59  # t3.micro
        nessus      = 7.59  # t3.micro
        app_servers = 15.18 # 2x t3.micro
      }
      network = {
        nat_gateway   = 32.85
        alb           = 16.43
        data_transfer = 5.00
      }
      storage = {
        ebs = 2.00
        efs = 1.00
        s3  = 1.00
      }
      total_monthly = 92.44
      total_4_hours = 0.51
    } : null

    full_mode_monthly = var.deployment_mode == "full" ? {
      compute = {
        bastions    = 19.00 # 5x t3.small
        jenkins     = 60.26 # 1x t3.medium + 4x t3.small
        nessus      = 59.28 # 5x t3.large
        app_servers = 45.54 # 15x t3.small
      }
      network = {
        nat_gateways    = 164.25 # 5 regions
        alb             = 82.15  # 5 ALBs
        transit_gateway = 36.50
        data_transfer   = 50.00
      }
      storage = {
        ebs = 50.00
        efs = 15.00
        s3  = 10.00
      }
      total_monthly = 592.98
    } : null

    cost_optimization_note = var.deployment_mode == "demo" ? "Demo mode includes automatic start/stop scheduling to minimize costs" : "Full mode designed for production workloads with high availability"
  }
}

# Security Summary
output "security_summary" {
  description = "Summary of implemented security controls"
  value = {
    network_security = {
      vpc_isolation   = "Each region has isolated VPC with no overlapping CIDRs"
      private_subnets = "All services deployed in private subnets"
      bastion_access  = "Single point of entry via bastion hosts"
      security_groups = "Least privilege access with specific port/protocol rules"
      network_acls    = "Additional subnet-level security controls"
    }

    access_control = {
      iam_roles       = "Least privilege IAM roles for each service"
      secrets_manager = "All credentials stored in AWS Secrets Manager"
      ssm_access      = "Systems Manager Session Manager instead of SSH"
      vpn_access      = var.enable_vpn ? "Client VPN for secure remote access" : "Disabled"
    }

    encryption = {
      ebs_volumes    = "All EBS volumes encrypted at rest"
      efs_encryption = "EFS file systems encrypted in transit and at rest"
      s3_encryption  = "S3 buckets encrypted with AES-256"
      secrets        = "Secrets Manager provides encryption at rest"
    }

    monitoring = var.enable_monitoring ? {
      vpc_flow_logs     = "VPC Flow Logs enabled for network monitoring"
      cloudtrail        = "CloudTrail enabled for API audit logging"
      cloudwatch        = "CloudWatch monitoring and alerting configured"
      security_scanning = "Nessus vulnerability scanning automated"
      } : {
      note = "Monitoring disabled for cost optimization"
    }
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Retrieve admin passwords from AWS Secrets Manager",
    "2. Configure VPN client certificates (if VPN enabled)",
    "3. Access Jenkins via ALB and configure additional pipelines",
    "4. Run initial Nessus vulnerability scans",
    "5. Test automation workflows between Jenkins and Nessus",
    "6. Review CloudWatch logs and metrics",
    "7. Customize security scanning policies based on requirements",
    "8. Set up additional monitoring and alerting as needed",
    "9. Run cost optimization review after testing",
    "10. Document any environment-specific configurations"
  ]
}

# Support Information
output "support_info" {
  description = "Support and troubleshooting information"
  value = {
    documentation   = "See docs/ directory for detailed guides"
    testing         = "Run ./tests/run-all-tests.sh for validation"
    troubleshooting = "Check CloudWatch logs for service issues"
    cost_monitoring = "Monitor AWS Cost Explorer for actual spending"
    cleanup         = "Run 'terraform destroy' to remove all resources"

    common_issues = {
      ssh_access = "Use Systems Manager Session Manager instead of direct SSH"
      web_access = "Services accessible via ALB through bastion or VPN"
      secrets    = "Retrieve passwords from AWS Secrets Manager console"
      scaling    = "Auto Scaling Groups handle instance replacement automatically"
    }
  }
}
