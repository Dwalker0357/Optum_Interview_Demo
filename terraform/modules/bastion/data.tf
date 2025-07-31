# Get latest Amazon Linux 2 AMI if not specified
data "aws_ami" "amazon_linux" {
  count = var.ami_id == "" ? 1 : 0

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

# Use specified AMI or default to latest Amazon Linux 2
locals {
  bastion_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux[0].id
}
