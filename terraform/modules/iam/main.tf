# IAM Module - Main Configuration
# Creates IAM roles, policies, and instance profiles for all services

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for current AWS partition
data "aws_partition" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Common tags for all IAM resources
locals {
  common_tags = merge(var.common_tags, {
    Module = "iam"
  })
}

# =============================================================================
# BASTION HOST IAM ROLE
# =============================================================================

resource "aws_iam_role" "bastion_role" {
  name               = "${var.environment}-${var.project_name}-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for bastion host with SSM and CloudWatch access"

  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-bastion-role"
    Service = "bastion"
    Purpose = "ssh-gateway"
  })
}

resource "aws_iam_policy" "bastion_policy" {
  name        = "${var.environment}-${var.project_name}-bastion-policy"
  description = "Policy for bastion host with least privilege access"
  policy      = data.aws_iam_policy_document.bastion_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "bastion_custom_policy" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = aws_iam_policy.bastion_policy.arn
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_managed_instance" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.environment}-${var.project_name}-bastion-profile"
  role = aws_iam_role.bastion_role.name

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-bastion-profile"
    Service = "bastion"
  })
}

# =============================================================================
# JENKINS MASTER IAM ROLE
# =============================================================================

resource "aws_iam_role" "jenkins_master_role" {
  name               = "${var.environment}-${var.project_name}-jenkins-master-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for Jenkins master with EC2, Secrets Manager, S3, and EFS access"

  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(local.common_tags, {
    Name      = "${var.environment}-${var.project_name}-jenkins-master-role"
    Service   = "jenkins"
    Component = "master"
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_master_poweruser" {
  role       = aws_iam_role.jenkins_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_master_iam" {
  role       = aws_iam_role.jenkins_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_master_ssm_managed_instance" {
  role       = aws_iam_role.jenkins_master_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins_master_profile" {
  name = "${var.environment}-${var.project_name}-jenkins-master-profile"
  role = aws_iam_role.jenkins_master_role.name

  tags = merge(local.common_tags, {
    Name      = "${var.environment}-${var.project_name}-jenkins-master-profile"
    Service   = "jenkins"
    Component = "master"
  })
}

# =============================================================================
# JENKINS AGENT IAM ROLE
# =============================================================================

resource "aws_iam_role" "jenkins_agent_role" {
  name               = "${var.environment}-${var.project_name}-jenkins-agent-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for Jenkins agents with limited EC2 and Ansible execution permissions"

  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(local.common_tags, {
    Name      = "${var.environment}-${var.project_name}-jenkins-agent-role"
    Service   = "jenkins"
    Component = "agent"
  })
}

resource "aws_iam_policy" "jenkins_agent_policy" {
  name        = "${var.environment}-${var.project_name}-jenkins-agent-policy"
  description = "Policy for Jenkins agents with limited execution permissions"
  policy      = data.aws_iam_policy_document.jenkins_agent_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "jenkins_agent_custom_policy" {
  role       = aws_iam_role.jenkins_agent_role.name
  policy_arn = aws_iam_policy.jenkins_agent_policy.arn
}

resource "aws_iam_role_policy_attachment" "jenkins_agent_ssm_managed_instance" {
  role       = aws_iam_role.jenkins_agent_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins_agent_profile" {
  name = "${var.environment}-${var.project_name}-jenkins-agent-profile"
  role = aws_iam_role.jenkins_agent_role.name

  tags = merge(local.common_tags, {
    Name      = "${var.environment}-${var.project_name}-jenkins-agent-profile"
    Service   = "jenkins"
    Component = "agent"
  })
}

# =============================================================================
# NESSUS SCANNER IAM ROLE
# =============================================================================

resource "aws_iam_role" "nessus_role" {
  name               = "${var.environment}-${var.project_name}-nessus-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for Nessus scanner with scanning permissions and S3 report storage"

  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-nessus-role"
    Service = "nessus"
    Purpose = "vulnerability-scanning"
  })
}

resource "aws_iam_policy" "nessus_policy" {
  name        = "${var.environment}-${var.project_name}-nessus-policy"
  description = "Policy for Nessus scanner with scanning and reporting permissions"
  policy      = data.aws_iam_policy_document.nessus_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "nessus_custom_policy" {
  role       = aws_iam_role.nessus_role.name
  policy_arn = aws_iam_policy.nessus_policy.arn
}

resource "aws_iam_role_policy_attachment" "nessus_ssm_managed_instance" {
  role       = aws_iam_role.nessus_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nessus_profile" {
  name = "${var.environment}-${var.project_name}-nessus-profile"
  role = aws_iam_role.nessus_role.name

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-nessus-profile"
    Service = "nessus"
  })
}

# =============================================================================
# APPLICATION SERVER IAM ROLE
# =============================================================================

resource "aws_iam_role" "app_server_role" {
  name               = "${var.environment}-${var.project_name}-app-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "IAM role for application servers with basic operations and CloudWatch access"

  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-app-server-role"
    Service = "application"
    Tier    = "web"
  })
}

resource "aws_iam_policy" "app_server_policy" {
  name        = "${var.environment}-${var.project_name}-app-server-policy"
  description = "Policy for application servers with basic operational permissions"
  policy      = data.aws_iam_policy_document.app_server_policy.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "app_server_custom_policy" {
  role       = aws_iam_role.app_server_role.name
  policy_arn = aws_iam_policy.app_server_policy.arn
}

resource "aws_iam_role_policy_attachment" "app_server_ssm_managed_instance" {
  role       = aws_iam_role.app_server_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_server_profile" {
  name = "${var.environment}-${var.project_name}-app-server-profile"
  role = aws_iam_role.app_server_role.name

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-app-server-profile"
    Service = "application"
  })
}

# =============================================================================
# CROSS-ACCOUNT TRUST ROLES (if required)
# =============================================================================

resource "aws_iam_role" "cross_account_admin_role" {
  count              = var.enable_cross_account_access ? 1 : 0
  name               = "${var.environment}-${var.project_name}-cross-account-admin-role"
  assume_role_policy = data.aws_iam_policy_document.cross_account_assume_role[0].json
  description        = "Cross-account role for administrative access from trusted accounts"

  tags = merge(local.common_tags, {
    Name    = "${var.environment}-${var.project_name}-cross-account-admin-role"
    Purpose = "cross-account-access"
  })
}

resource "aws_iam_role_policy_attachment" "cross_account_admin_policy" {
  count      = var.enable_cross_account_access ? 1 : 0
  role       = aws_iam_role.cross_account_admin_role[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/PowerUserAccess"
}

# =============================================================================
# SERVICE-LINKED ROLES
# =============================================================================

resource "aws_iam_service_linked_role" "efs_service_role" {
  count            = var.create_service_linked_roles ? 1 : 0
  aws_service_name = "elasticfilesystem.amazonaws.com"
  description      = "Service-linked role for Amazon EFS"

  tags = local.common_tags
}

resource "aws_iam_service_linked_role" "autoscaling_service_role" {
  count            = var.create_service_linked_roles ? 1 : 0
  aws_service_name = "autoscaling.amazonaws.com"
  description      = "Service-linked role for AWS Auto Scaling"

  tags = local.common_tags
}

# =============================================================================
# POLICY DOCUMENTS (Include from separate files)
# =============================================================================

# EC2 Assume Role Policy
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }
}

# Cross-account assume role policy
data "aws_iam_policy_document" "cross_account_assume_role" {
  count = var.enable_cross_account_access ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = var.trusted_account_ids
    }
    actions = ["sts:AssumeRole"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "aws:MultiFactorAuthAge"
      values   = ["3600"]
    }
  }
}

# Include policy documents from separate files
data "aws_iam_policy_document" "bastion_policy" {
  source_policy_documents = [
    file("${path.module}/policies/bastion-policy.json")
  ]
}

data "aws_iam_policy_document" "jenkins_master_policy" {
  source_policy_documents = [
    file("${path.module}/policies/jenkins-master-policy.json")
  ]
}

data "aws_iam_policy_document" "jenkins_agent_policy" {
  source_policy_documents = [
    file("${path.module}/policies/jenkins-agent-policy.json")
  ]
}

data "aws_iam_policy_document" "nessus_policy" {
  source_policy_documents = [
    file("${path.module}/policies/nessus-policy.json")
  ]
}

data "aws_iam_policy_document" "app_server_policy" {
  source_policy_documents = [
    file("${path.module}/policies/app-server-policy.json")
  ]
}
