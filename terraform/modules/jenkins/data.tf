# Jenkins Module Data Sources

# Get current region
data "aws_region" "current" {}

# Get current caller identity
data "aws_caller_identity" "current" {}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
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

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get VPC information
data "aws_vpc" "main" {
  id = var.vpc_id
}

# Get subnet information
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

# Commented out due to computed for_each issue
# data "aws_subnet" "private" {
#   for_each = toset(var.private_subnet_ids)
#   id       = each.value
# }

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC endpoint services are now managed by the VPC module to avoid duplication
# and prevent hitting AWS VPC endpoint limits

# Get the latest Jenkins LTS version (for reference in user data)
data "external" "jenkins_version" {
  program = ["bash", "-c", <<-EOF
    VERSION=$(curl -s https://api.github.com/repos/jenkinsci/jenkins/releases | jq -r '[.[] | select(.tag_name | test("^[0-9]+(\\.[0-9]+)*$"))] | .[0].tag_name')
    echo "{\"version\":\"$VERSION\"}"
  EOF
  ]
}

# SSM Parameter for Amazon Linux 2 AMI ID
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# Get current AWS partition
data "aws_partition" "current" {}

# IAM policy document for EFS access
data "aws_iam_policy_document" "efs_policy" {
  statement {
    sid    = "AllowEFSAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.jenkins_master_role_arn, var.jenkins_agent_role_arn]
    }

    actions = [
      "elasticfilesystem:CreateFileSystem",
      "elasticfilesystem:DescribeFileSystem",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientRootAccess"
    ]

    resources = [aws_efs_file_system.jenkins.arn]
  }
}

# IAM policy document for instance profile trust relationship
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM policy document for Auto Scaling service role
data "aws_iam_policy_document" "autoscaling_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["autoscaling.amazonaws.com"]
    }
  }
}

# IAM policy document for CloudWatch access
data "aws_iam_policy_document" "cloudwatch_policy" {
  statement {
    sid    = "CloudWatchAccess"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData",
      "ec2:DescribeVolumes",
      "ec2:DescribeTags",
      "logs:PutLogEvents",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams"
    ]

    resources = ["*"]
  }
}

# IAM policy document for Jenkins master additional permissions
data "aws_iam_policy_document" "jenkins_master_additional" {
  statement {
    sid    = "JenkinsCloudAccess"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeLaunchTemplates",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "JenkinsAgentManagement"
    effect = "Allow"

    actions = [
      "ec2:GetPasswordData",
      "ec2:DescribeKeyPairs",
      "ec2:DescribeSpotInstanceRequests",
      "ec2:DescribeSpotPriceHistory",
      "ec2:RequestSpotInstances",
      "ec2:CancelSpotInstanceRequests",
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:ImportKeyPair"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "JenkinsEFSAccess"
    effect = "Allow"

    actions = [
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:CreateMountTarget",
      "elasticfilesystem:DeleteMountTarget"
    ]

    resources = [aws_efs_file_system.jenkins.arn]
  }
}

# Get Route53 hosted zone (if exists)
data "aws_route53_zone" "internal" {
  count        = var.environment != "demo" ? 1 : 0
  name         = "${var.environment}.internal"
  private_zone = true
}

# Local data for plugin versions
locals {
  plugin_versions = {
    "ant"                       = "475.vf34069fef73c"
    "antisamy-markup-formatter" = "159.v25b_c67cd35fb_"
    "build-timeout"             = "1.31"
    "credentials-binding"       = "523.vd859a_4b_122e6"
    "timestamper"               = "1.25"
    "ws-cleanup"                = "0.45"
    "github"                    = "1.37.3.1"
    "github-branch-source"      = "1703.vd5a_2b_29c6cdc"
    "pipeline-github-lib"       = "42.v0739460cda_c4"
    "pipeline-stage-view"       = "2.25"
    "git"                       = "5.0.0"
    "ssh-slaves"                = "2.916.vd4c3d4a_da_478"
    "matrix-auth"               = "3.1.10"
    "pam-auth"                  = "1.10"
    "ldap"                      = "682.v7b_544c9d1512"
    "email-ext"                 = "2.96"
    "mailer"                    = "463.vedf8358e006b_"
    "slack"                     = "664.vc9a_90f8b_c24a_"
    "ansible"                   = "403.v8d0ca_dcb_b_502"
    "ec2"                       = "2.0.6"
    "aws-credentials"           = "191.vcb_f183ce58b_9"
    "s3"                        = "0.12.0"
    "pipeline-aws"              = "1.43"
    "docker-workflow"           = "572.v950f58993843"
    "blueocean"                 = "1.27.3"
    "prometheus"                = "2.2.3"
    "monitoring"                = "1.98.0"
  }
}
