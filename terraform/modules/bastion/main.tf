# Bastion Host for Secure Access

# Launch Template for Bastion
resource "aws_launch_template" "bastion" {
  name_prefix   = "${var.name_prefix}-bastion-"
  image_id      = local.bastion_ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name

  vpc_security_group_ids = [var.security_group_id]

  iam_instance_profile {
    name = var.bastion_instance_profile
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 20
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${var.name_prefix}-bastion"
      Type = "bastion-host"
    })
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    aws_region = var.aws_region
  }))

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-bastion-lt"
    Type = "launch-template"
  })
}

# Auto Scaling Group for High Availability
resource "aws_autoscaling_group" "bastion" {
  name                      = "${var.name_prefix}-bastion-asg"
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = []
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = 2 # HA: One bastion per AZ
  max_size         = 2
  desired_capacity = 2

  # Ensure even distribution across AZs for HA
  default_cooldown = 300
  force_delete     = true

  # Enable AZ rebalancing to distribute instances evenly
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-bastion-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Note: IAM roles and instance profiles are now managed by the IAM module
# This eliminates duplication and ensures consistent permissions across the infrastructure

# CloudWatch Log Group for Bastion
resource "aws_cloudwatch_log_group" "bastion" {
  name              = "/aws/ec2/bastion/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-bastion-logs"
    Type = "cloudwatch-log-group"
  })
}

# Elastic IP for Bastion (optional)
resource "aws_eip" "bastion" {
  count = var.create_eip ? 1 : 0

  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-bastion-eip"
    Type = "elastic-ip"
  })
}

# EIP Association (handled by user-data script)
resource "aws_ssm_parameter" "bastion_eip" {
  count = var.create_eip ? 1 : 0

  name  = "/${var.name_prefix}/bastion/eip-allocation-id"
  type  = "String"
  value = aws_eip.bastion[0].allocation_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-bastion-eip-param"
    Type = "ssm-parameter"
  })
}
