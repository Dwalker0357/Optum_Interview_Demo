# IAM Module Outputs

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "bastion_role_arn" {
  description = "ARN of the bastion host IAM role"
  value       = aws_iam_role.bastion_role.arn
}

output "bastion_role_name" {
  description = "Name of the bastion host IAM role"
  value       = aws_iam_role.bastion_role.name
}

output "jenkins_master_role_arn" {
  description = "ARN of the Jenkins master IAM role"
  value       = aws_iam_role.jenkins_master_role.arn
}

output "jenkins_master_role_name" {
  description = "Name of the Jenkins master IAM role"
  value       = aws_iam_role.jenkins_master_role.name
}

output "jenkins_agent_role_arn" {
  description = "ARN of the Jenkins agent IAM role"
  value       = aws_iam_role.jenkins_agent_role.arn
}

output "jenkins_agent_role_name" {
  description = "Name of the Jenkins agent IAM role"
  value       = aws_iam_role.jenkins_agent_role.name
}

output "nessus_role_arn" {
  description = "ARN of the Nessus scanner IAM role"
  value       = aws_iam_role.nessus_role.arn
}

output "nessus_role_name" {
  description = "Name of the Nessus scanner IAM role"
  value       = aws_iam_role.nessus_role.name
}

output "app_server_role_arn" {
  description = "ARN of the application server IAM role"
  value       = aws_iam_role.app_server_role.arn
}

output "app_server_role_name" {
  description = "Name of the application server IAM role"
  value       = aws_iam_role.app_server_role.name
}

output "cross_account_admin_role_arn" {
  description = "ARN of the cross-account admin IAM role"
  value       = var.enable_cross_account_access ? aws_iam_role.cross_account_admin_role[0].arn : null
}

output "cross_account_admin_role_name" {
  description = "Name of the cross-account admin IAM role"
  value       = var.enable_cross_account_access ? aws_iam_role.cross_account_admin_role[0].name : null
}

# =============================================================================
# INSTANCE PROFILE OUTPUTS
# =============================================================================

output "bastion_instance_profile_arn" {
  description = "ARN of the bastion host instance profile"
  value       = aws_iam_instance_profile.bastion_profile.arn
}

output "bastion_instance_profile_name" {
  description = "Name of the bastion host instance profile"
  value       = aws_iam_instance_profile.bastion_profile.name
}

output "jenkins_master_instance_profile_arn" {
  description = "ARN of the Jenkins master instance profile"
  value       = aws_iam_instance_profile.jenkins_master_profile.arn
}

output "jenkins_master_instance_profile_name" {
  description = "Name of the Jenkins master instance profile"
  value       = aws_iam_instance_profile.jenkins_master_profile.name
}

output "jenkins_agent_instance_profile_arn" {
  description = "ARN of the Jenkins agent instance profile"
  value       = aws_iam_instance_profile.jenkins_agent_profile.arn
}

output "jenkins_agent_instance_profile_name" {
  description = "Name of the Jenkins agent instance profile"
  value       = aws_iam_instance_profile.jenkins_agent_profile.name
}

output "nessus_instance_profile_arn" {
  description = "ARN of the Nessus scanner instance profile"
  value       = aws_iam_instance_profile.nessus_profile.arn
}

output "nessus_instance_profile_name" {
  description = "Name of the Nessus scanner instance profile"
  value       = aws_iam_instance_profile.nessus_profile.name
}

output "app_server_instance_profile_arn" {
  description = "ARN of the application server instance profile"
  value       = aws_iam_instance_profile.app_server_profile.arn
}

output "app_server_instance_profile_name" {
  description = "Name of the application server instance profile"
  value       = aws_iam_instance_profile.app_server_profile.name
}

# =============================================================================
# IAM POLICY OUTPUTS
# =============================================================================

output "bastion_policy_arn" {
  description = "ARN of the bastion host IAM policy"
  value       = aws_iam_policy.bastion_policy.arn
}

output "jenkins_master_policy_arn" {
  description = "ARN of the Jenkins master IAM policy"
  value       = "arn:aws:iam::aws:policy/PowerUserAccess"
}

output "jenkins_agent_policy_arn" {
  description = "ARN of the Jenkins agent IAM policy"
  value       = aws_iam_policy.jenkins_agent_policy.arn
}

output "nessus_policy_arn" {
  description = "ARN of the Nessus scanner IAM policy"
  value       = aws_iam_policy.nessus_policy.arn
}

output "app_server_policy_arn" {
  description = "ARN of the application server IAM policy"
  value       = aws_iam_policy.app_server_policy.arn
}

# =============================================================================
# SERVICE-LINKED ROLE OUTPUTS
# =============================================================================

output "efs_service_linked_role_arn" {
  description = "ARN of the EFS service-linked role"
  value       = var.create_service_linked_roles ? aws_iam_service_linked_role.efs_service_role[0].arn : null
}

output "autoscaling_service_linked_role_arn" {
  description = "ARN of the Auto Scaling service-linked role"
  value       = var.create_service_linked_roles ? aws_iam_service_linked_role.autoscaling_service_role[0].arn : null
}

# =============================================================================
# COMPREHENSIVE ROLE MAPPING OUTPUTS
# =============================================================================

output "role_mappings" {
  description = "Map of service names to their IAM role ARNs"
  value = {
    bastion             = aws_iam_role.bastion_role.arn
    jenkins_master      = aws_iam_role.jenkins_master_role.arn
    jenkins_agent       = aws_iam_role.jenkins_agent_role.arn
    nessus              = aws_iam_role.nessus_role.arn
    app_server          = aws_iam_role.app_server_role.arn
    cross_account_admin = var.enable_cross_account_access ? aws_iam_role.cross_account_admin_role[0].arn : null
  }
}

output "instance_profile_mappings" {
  description = "Map of service names to their instance profile names"
  value = {
    bastion        = aws_iam_instance_profile.bastion_profile.name
    jenkins_master = aws_iam_instance_profile.jenkins_master_profile.name
    jenkins_agent  = aws_iam_instance_profile.jenkins_agent_profile.name
    nessus         = aws_iam_instance_profile.nessus_profile.name
    app_server     = aws_iam_instance_profile.app_server_profile.name
  }
}

output "policy_mappings" {
  description = "Map of service names to their IAM policy ARNs"
  value = {
    bastion        = aws_iam_policy.bastion_policy.arn
    jenkins_master = "arn:aws:iam::aws:policy/PowerUserAccess"
    jenkins_agent  = aws_iam_policy.jenkins_agent_policy.arn
    nessus         = aws_iam_policy.nessus_policy.arn
    app_server     = aws_iam_policy.app_server_policy.arn
  }
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "demo_mode_enabled" {
  description = "Whether demo mode is enabled"
  value       = var.demo_mode
}

output "cross_account_access_enabled" {
  description = "Whether cross-account access is enabled"
  value       = var.enable_cross_account_access
}

output "trusted_account_ids" {
  description = "List of trusted account IDs for cross-account access"
  value       = var.trusted_account_ids
  sensitive   = true
}

# =============================================================================
# RESOURCE IDENTIFIERS FOR OTHER MODULES
# =============================================================================

output "all_role_arns" {
  description = "List of all IAM role ARNs created by this module"
  value = compact([
    aws_iam_role.bastion_role.arn,
    aws_iam_role.jenkins_master_role.arn,
    aws_iam_role.jenkins_agent_role.arn,
    aws_iam_role.nessus_role.arn,
    aws_iam_role.app_server_role.arn,
    var.enable_cross_account_access ? aws_iam_role.cross_account_admin_role[0].arn : null
  ])
}

output "all_instance_profile_names" {
  description = "List of all instance profile names created by this module"
  value = [
    aws_iam_instance_profile.bastion_profile.name,
    aws_iam_instance_profile.jenkins_master_profile.name,
    aws_iam_instance_profile.jenkins_agent_profile.name,
    aws_iam_instance_profile.nessus_profile.name,
    aws_iam_instance_profile.app_server_profile.name
  ]
}

output "all_policy_arns" {
  description = "List of all custom IAM policy ARNs created by this module"
  value = [
    aws_iam_policy.bastion_policy.arn,
    "arn:aws:iam::aws:policy/PowerUserAccess",
    aws_iam_policy.jenkins_agent_policy.arn,
    aws_iam_policy.nessus_policy.arn,
    aws_iam_policy.app_server_policy.arn
  ]
}

# =============================================================================
# METADATA OUTPUTS
# =============================================================================

output "module_version" {
  description = "Version of the IAM module"
  value       = "1.0.0"
}

output "created_resources_count" {
  description = "Number of IAM resources created"
  value = {
    roles                = 5 + (var.enable_cross_account_access ? 1 : 0)
    policies             = 5
    instance_profiles    = 5
    service_linked_roles = var.create_service_linked_roles ? 2 : 0
  }
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}
