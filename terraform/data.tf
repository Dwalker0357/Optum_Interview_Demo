# Data sources for existing resources and AMIs

# Current AWS caller identity
data "aws_caller_identity" "current" {}

# Current AWS region
data "aws_region" "current" {}

# Available AZs in each region
data "aws_availability_zones" "available" {
  for_each = toset(local.deployment_regions)

  state = "available"
}

# Latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  for_each = toset(local.deployment_regions)

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  for_each = toset(local.deployment_regions)

  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Note: Secrets are created by the secrets module and accessed via module outputs
# Removed duplicate data sources that were reading locally-created secrets

# Create EC2 key pair from Secrets Manager TLS key
resource "aws_key_pair" "main" {
  key_name   = var.key_pair_name
  public_key = module.secrets.ssh_public_key

  lifecycle {
    ignore_changes = [public_key]
  }
}

# Instance profile for Systems Manager
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM policy for EC2 instances to access Secrets Manager
data "aws_iam_policy_document" "secrets_access" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.environment}/*"
    ]
  }
}

# IAM policy for Systems Manager access
data "aws_iam_policy_document" "ssm_access" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:SendCommand",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
      "ssm:GetConnectionStatus",
      "ssm:DescribeInstanceAssociations",
      "ssm:DescribeInstanceAssociationsStatus",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]
    resources = ["*"]
  }
}

# CloudWatch agent configuration
data "aws_iam_policy_document" "cloudwatch_agent" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

# Route53 hosted zone (if it exists and domain name is provided, but not for demo.internal)
data "aws_route53_zone" "main" {
  count        = !var.create_dns_zone && var.domain_name != "" && var.domain_name != "demo.internal" ? 1 : 0
  name         = var.domain_name
  private_zone = false
}
