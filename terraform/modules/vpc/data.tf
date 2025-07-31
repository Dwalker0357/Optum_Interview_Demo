# Data sources for VPC module

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get available AZs in current region
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Get VPC endpoint service names for the current region
# S3 VPC endpoint removed - NAT Gateway provides S3 access
# data "aws_vpc_endpoint_service" "s3" {
#   count        = contains(var.vpc_endpoints_services, "s3") ? 1 : 0
#   service      = "s3"
#   service_type = "Gateway"
# }

data "aws_vpc_endpoint_service" "ec2" {
  count   = contains(var.vpc_endpoints_services, "ec2") ? 1 : 0
  service = "ec2"
}

data "aws_vpc_endpoint_service" "secretsmanager" {
  count   = contains(var.vpc_endpoints_services, "secretsmanager") ? 1 : 0
  service = "secretsmanager"
}

# IAM role for VPC Flow Logs
data "aws_iam_policy_document" "flow_logs_assume_role" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "flow_logs_policy" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}
