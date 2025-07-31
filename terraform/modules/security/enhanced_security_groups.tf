# Enhanced Security Groups with Hardened Rules
# These complement the existing security groups with improved security posture

# Enhanced Bastion Security Group (Hardened)
resource "aws_security_group" "bastion_enhanced" {
  name_prefix = "${var.name_prefix}-bastion-enhanced-"
  vpc_id      = var.vpc_id

  # SSH only from specifically authorized IPs (no 0.0.0.0/0)
  ingress {
    description = "SSH from VPN and authorized networks only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # HTTPS for Session Manager from VPC only
  ingress {
    description = "HTTPS for Session Manager from VPC only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # HARDENED: Restrict egress to specific protocols and destinations
  egress {
    description = "HTTPS to internet for package updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "HTTP to internet for package updates"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "SSH to VPC subnets only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS to internet"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "DNS to internet"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name          = "${var.name_prefix}-bastion-enhanced-sg"
    Type          = "security-group"
    SecurityLevel = "hardened"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced Jenkins Security Group (Hardened)
resource "aws_security_group" "jenkins_enhanced" {
  name_prefix = "${var.name_prefix}-jenkins-enhanced-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_enhanced.id]
  }

  ingress {
    description     = "Jenkins web interface from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_enhanced.id]
  }

  ingress {
    description = "Jenkins agent communication"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # HARDENED: Restrict egress to specific protocols
  egress {
    description = "HTTPS to internet for plugins and updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "HTTP to VPC for app deployments"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to VPC for secure communications"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Jenkins agent communication"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "DNS resolution over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name          = "${var.name_prefix}-jenkins-enhanced-sg"
    Type          = "security-group"
    SecurityLevel = "hardened"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced Nessus Security Group (Hardened)
resource "aws_security_group" "nessus_enhanced" {
  name_prefix = "${var.name_prefix}-nessus-enhanced-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_enhanced.id]
  }

  ingress {
    description     = "ICMP ping from bastion"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.bastion_enhanced.id]
  }

  ingress {
    description     = "Nessus web interface from ALB"
    from_port       = 8834
    to_port         = 8834
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_enhanced.id]
  }

  # HARDENED: Specific egress rules for Nessus operations
  egress {
    description = "HTTPS for Nessus updates and plugins"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "Nessus scanning to VPC targets"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "DNS resolution over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name          = "${var.name_prefix}-nessus-enhanced-sg"
    Type          = "security-group"
    SecurityLevel = "hardened"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced ALB Security Group (Hardened)
resource "aws_security_group" "alb_enhanced" {
  name_prefix = "${var.name_prefix}-alb-enhanced-"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from authorized networks only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "HTTP from authorized networks only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  # HARDENED: Only allow egress to VPC services, no internet access
  egress {
    description = "HTTP to VPC services only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to VPC services only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Jenkins communication"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Nessus communication"
    from_port   = 8834
    to_port     = 8834
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name          = "${var.name_prefix}-alb-enhanced-sg"
    Type          = "security-group"
    SecurityLevel = "hardened"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced App Servers Security Group (Hardened)
resource "aws_security_group" "app_servers_enhanced" {
  name_prefix = "${var.name_prefix}-app-enhanced-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_enhanced.id]
  }

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_enhanced.id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_enhanced.id]
  }

  ingress {
    description     = "Nessus scanning"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.nessus_enhanced.id]
  }

  # Intentional vulnerabilities for demo (restricted to VPC only)
  ingress {
    description = "Intentional vulnerability - Telnet (VPC only)"
    from_port   = 23
    to_port     = 23
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  ingress {
    description = "Intentional vulnerability - FTP (VPC only)"
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # HARDENED: Restrict egress to specific protocols
  egress {
    description = "HTTPS for package updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "HTTP for package updates"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "DNS resolution over TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "NTP time sync"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  egress {
    description = "Internal VPC communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name          = "${var.name_prefix}-app-servers-enhanced-sg"
    Type          = "security-group"
    SecurityLevel = "hardened"
  })

  lifecycle {
    create_before_destroy = true
  }
}
