# Security Groups and Network ACLs for Optum UK Demo

# Bastion Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${var.name_prefix}-bastion-"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from VPN and authorized networks only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "HTTPS for Session Manager from VPC only"
    from_port   = 443
    to_port     = 443
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
    Name = "${var.name_prefix}-bastion-sg"
    Type = "security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Jenkins Security Group
resource "aws_security_group" "jenkins" {
  name_prefix = "${var.name_prefix}-jenkins-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "Jenkins web interface from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Jenkins web interface from Nessus for vulnerability scanning"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.nessus.id]
  }

  ingress {
    description     = "SSH from Nessus for vulnerability scanning"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nessus.id]
  }

  ingress {
    description = "Jenkins agent communication"
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-jenkins-sg"
    Type = "security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Nessus Security Group
resource "aws_security_group" "nessus" {
  name_prefix = "${var.name_prefix}-nessus-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "ICMP ping from bastion"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "Nessus web interface from ALB"
    from_port       = 8834
    to_port         = 8834
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-nessus-sg"
    Type = "security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.name_prefix}-alb-"
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

  egress {
    description = "All outbound traffic to VPC services"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb-sg"
    Type = "security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# App Servers Security Group
resource "aws_security_group" "app_servers" {
  name_prefix = "${var.name_prefix}-app-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "SSH from Nessus for vulnerability scanning"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nessus.id]
  }

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "HTTP from Nessus for vulnerability scanning"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nessus.id]
  }

  ingress {
    description     = "HTTPS from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Nessus scanning"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.nessus.id]
  }

  ingress {
    description = "Intentional vulnerability - Telnet"
    from_port   = 23
    to_port     = 23
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  ingress {
    description = "Intentional vulnerability - FTP"
    from_port   = 21
    to_port     = 21
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["203.45.67.89/32"] # Developer IP for demo environment
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-app-servers-sg"
    Type = "security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Network ACL for Public Subnets
resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids



  ingress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-public-nacl"
    Type = "network-acl"
  })
}

# Network ACL for Private Subnets
resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-private-nacl"
    Type = "network-acl"
  })
}
