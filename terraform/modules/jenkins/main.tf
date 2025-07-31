# Jenkins Module Main Configuration

locals {
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project
    Module      = "jenkins"
    ManagedBy   = "terraform"
  })

  # Jenkins configuration
  jenkins_home = "/var/lib/jenkins"
  jenkins_user = "jenkins"
  jenkins_port = 8080
  agent_port   = 50000

  # Instance configuration based on deployment mode
  master_instance_type = var.deployment_mode == "demo" ? var.instance_sizes.demo.jenkins : var.instance_sizes.full.jenkins
  agent_instance_type  = var.deployment_mode == "demo" ? "t3.micro" : "t3.small"

  # Use spot instances for demo mode
  use_spot_instances = var.deployment_mode == "demo"
}

# S3 Bucket for Jenkins artifacts
resource "aws_s3_bucket" "jenkins_artifacts" {
  bucket = "${var.project}-jenkins-artifacts-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${var.project}-jenkins-artifacts"
    Type = "s3-bucket"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "jenkins_artifacts" {
  bucket = aws_s3_bucket.jenkins_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_artifacts" {
  bucket = aws_s3_bucket.jenkins_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "jenkins_artifacts" {
  bucket = aws_s3_bucket.jenkins_artifacts.id

  rule {
    id     = "cleanup_old_artifacts"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.artifact_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# S3 object with fully rendered Jenkins script (variables already substituted)
resource "aws_s3_object" "jenkins_master_script" {
  bucket = aws_s3_bucket.jenkins_artifacts.id
  key    = "bootstrap/jenkins-master-init.sh"
  content = templatefile("${path.module}/userdata/jenkins-master-init.sh", {
    jenkins_home       = local.jenkins_home
    jenkins_user       = local.jenkins_user
    jenkins_port       = local.jenkins_port
    agent_port         = local.agent_port
    efs_id             = aws_efs_file_system.jenkins.id
    region             = var.region
    project            = var.project
    environment        = var.environment
    s3_bucket          = aws_s3_bucket.jenkins_artifacts.bucket
    secrets_arn        = var.jenkins_secrets_arn
    webhook_secret_arn = var.nessus_webhook_secret_arn
    deployment_mode    = var.deployment_mode
    terraform_version  = "1.9.7"
  })

  # AWS S3 object tag limit is 10, so no tags added
}

resource "aws_s3_object" "jenkins_agent_script" {
  bucket = aws_s3_bucket.jenkins_artifacts.id
  key    = "bootstrap/jenkins-agent-init.sh"
  content = templatefile("${path.module}/userdata/jenkins-agent-init.sh", {
    jenkins_master_url = "http://${aws_autoscaling_group.jenkins_master.name}:${local.jenkins_port}"
    jenkins_user       = local.jenkins_user
    region             = var.region
    project            = var.project
    environment        = var.environment
    s3_bucket          = aws_s3_bucket.jenkins_artifacts.bucket
    secrets_arn        = var.jenkins_secrets_arn
    efs_file_system_id = aws_efs_file_system.jenkins.id
  })

  # AWS S3 object tag limit is 10, so no tags added
}

# EFS for Jenkins persistent storage
resource "aws_efs_file_system" "jenkins" {
  creation_token                  = "${var.project}-jenkins-efs"
  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = var.deployment_mode == "demo" ? 10 : 100

  encrypted = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-jenkins-efs"
    Type = "efs"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "jenkins" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.jenkins.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${var.project}-jenkins-efs-"
  description = "Security group for Jenkins EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_master.id, aws_security_group.jenkins_agents.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-jenkins-efs-sg"
    Type = "security-group"
  })
}

# Security Group for Jenkins Master
resource "aws_security_group" "jenkins_master" {
  name_prefix = "${var.project}-jenkins-master-"
  description = "Security group for Jenkins master"
  vpc_id      = var.vpc_id

  # Jenkins UI access from ALB
  ingress {
    from_port       = local.jenkins_port
    to_port         = local.jenkins_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  # Agent communication - will be added as separate rule to avoid cycle

  # SSH access from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-jenkins-master-sg"
    Type = "security-group"
  })
}

# Security Group for Jenkins Agents
resource "aws_security_group" "jenkins_agents" {
  name_prefix = "${var.project}-jenkins-agents-"
  description = "Security group for Jenkins agents"
  vpc_id      = var.vpc_id

  # SSH access from master for agent provisioning - will be added as separate rule to avoid cycle

  # SSH access from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-jenkins-agents-sg"
    Type = "security-group"
  })
}

# Separate security group rules to avoid circular dependency
resource "aws_security_group_rule" "jenkins_master_agent_communication" {
  type                     = "ingress"
  from_port                = local.agent_port
  to_port                  = local.agent_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.jenkins_agents.id
  security_group_id        = aws_security_group.jenkins_master.id
}

resource "aws_security_group_rule" "jenkins_agents_ssh_from_master" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.jenkins_master.id
  security_group_id        = aws_security_group.jenkins_agents.id
}

# Note: IAM roles and instance profiles are now managed by the IAM module
# This eliminates duplication and ensures consistent permissions across the infrastructure

# Launch Template for Jenkins Master
resource "aws_launch_template" "jenkins_master" {
  name_prefix   = "${var.project}-jenkins-master-"
  image_id      = var.ami_id
  instance_type = local.master_instance_type
  key_name      = var.key_pair_name

  iam_instance_profile {
    name = var.jenkins_master_instance_profile
  }

  vpc_security_group_ids = [aws_security_group.jenkins_master.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
set -e
exec > >(tee /var/log/jenkins-bootstrap.log)
exec 2>&1

echo "=== Jenkins Bootstrap - Downloading Full Setup Script ==="

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    yum update -y
    yum install -y awscli
fi

# Download the full Jenkins setup script (with all variables pre-populated)
aws s3 cp s3://${aws_s3_bucket.jenkins_artifacts.bucket}/${aws_s3_object.jenkins_master_script.key} /tmp/jenkins-full-setup.sh --region ${var.region}
chmod +x /tmp/jenkins-full-setup.sh

echo "=== Executing Full Jenkins Setup Script ==="
/tmp/jenkins-full-setup.sh

echo "=== Jenkins bootstrap completed ==="
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project}-jenkins-master"
      Role = "jenkins-master"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${var.project}-jenkins-master-volume"
    })
  }

  tags = local.common_tags
}

# Auto Scaling Group for Jenkins Master (for auto-recovery)
resource "aws_autoscaling_group" "jenkins_master" {
  name                      = "${var.project}-jenkins-master-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [var.alb_target_group_arn]
  health_check_type         = "EC2"
  health_check_grace_period = 900

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  launch_template {
    id      = aws_launch_template.jenkins_master.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-jenkins-master-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

# Launch Template for Jenkins Agents
resource "aws_launch_template" "jenkins_agents" {
  name_prefix   = "${var.project}-jenkins-agents-"
  image_id      = var.ami_id
  instance_type = local.agent_instance_type
  key_name      = var.key_pair_name

  iam_instance_profile {
    name = var.jenkins_agent_instance_profile
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

  vpc_security_group_ids = [aws_security_group.jenkins_agents.id]

  # Use spot instances for demo mode
  dynamic "instance_market_options" {
    for_each = local.use_spot_instances ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        spot_instance_type = "one-time"
      }
    }
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
set -e
exec > >(tee /var/log/jenkins-agent-bootstrap.log)
exec 2>&1

echo "=== Jenkins Agent Bootstrap - Downloading Full Setup Script ==="

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    yum update -y
    yum install -y awscli
fi

# Download the full Jenkins agent setup script (with all variables pre-populated)
aws s3 cp s3://${aws_s3_bucket.jenkins_artifacts.bucket}/${aws_s3_object.jenkins_agent_script.key} /tmp/jenkins-agent-setup.sh --region ${var.region}
chmod +x /tmp/jenkins-agent-setup.sh

echo "=== Executing Full Jenkins Agent Setup Script ==="
/tmp/jenkins-agent-setup.sh

echo "=== Jenkins agent bootstrap completed ==="
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project}-jenkins-agent"
      Role = "jenkins-agent"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${var.project}-jenkins-agent-volume"
    })
  }

  tags = local.common_tags
}

# Auto Scaling Group for Jenkins Agents
resource "aws_autoscaling_group" "jenkins_agents" {
  name                      = "${var.project}-jenkins-agents-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = var.agents_config.min_size
  max_size         = var.agents_config.max_size
  desired_capacity = var.agents_config.desired_capacity

  launch_template {
    id      = aws_launch_template.jenkins_agents.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-jenkins-agents-asg"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

# CloudWatch Log Group for Jenkins
resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "/aws/ec2/jenkins/${var.project}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project}-jenkins-logs"
    Type = "cloudwatch-log-group"
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "jenkins_master_cpu" {
  alarm_name          = "${var.project}-jenkins-master-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins master cpu utilization"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_master.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "jenkins_agents_cpu" {
  alarm_name          = "${var.project}-jenkins-agents-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors jenkins agents cpu utilization"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_agents.name
  }

  tags = local.common_tags
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "agents_scale_up" {
  name                   = "${var.project}-jenkins-agents-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.jenkins_agents.name
}

resource "aws_autoscaling_policy" "agents_scale_down" {
  name                   = "${var.project}-jenkins-agents-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.jenkins_agents.name
}

# CloudWatch Metric Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "agents_cpu_high" {
  alarm_name          = "${var.project}-jenkins-agents-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "Scale up when CPU > 70%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_agents.name
  }

  alarm_actions = [aws_autoscaling_policy.agents_scale_up.arn]

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "agents_cpu_low" {
  alarm_name          = "${var.project}-jenkins-agents-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "Scale down when CPU < 20%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.jenkins_agents.name
  }

  alarm_actions = [aws_autoscaling_policy.agents_scale_down.arn]

  tags = local.common_tags
}
