# Application Load Balancer for Internal Services

# ALB
resource "aws_lb" "main" {
  name               = "${var.name_prefix}-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = "alb"
    enabled = var.enable_access_logs
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-alb"
    Type = "application-load-balancer"
  })
}

# Generate self-signed certificate for demo purposes
resource "tls_private_key" "demo_ca" {
  count     = var.domain_name != "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "demo_ca" {
  count           = var.domain_name != "" ? 1 : 0
  private_key_pem = tls_private_key.demo_ca[0].private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "Demo CA"
  }

  validity_period_hours = 168 # 7 days for demo

  is_ca_certificate = true

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
  ]
}

# Generate certificate for the domain
resource "tls_private_key" "demo_cert" {
  count     = var.domain_name != "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "demo_cert" {
  count           = var.domain_name != "" ? 1 : 0
  private_key_pem = tls_private_key.demo_cert[0].private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "Demo Organization"
  }

  dns_names = [
    var.domain_name,
    "*.${var.domain_name}",
    "jenkins.${var.domain_name}",
    "nessus.${var.domain_name}",
    "app.${var.domain_name}"
  ]
}

resource "tls_locally_signed_cert" "demo_cert" {
  count              = var.domain_name != "" ? 1 : 0
  cert_request_pem   = tls_cert_request.demo_cert[0].cert_request_pem
  ca_private_key_pem = tls_private_key.demo_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.demo_ca[0].cert_pem

  validity_period_hours = 168 # 7 days for demo

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Import the certificate into ACM
resource "aws_acm_certificate" "main" {
  count             = var.domain_name != "" ? 1 : 0
  private_key       = tls_private_key.demo_cert[0].private_key_pem
  certificate_body  = tls_locally_signed_cert.demo_cert[0].cert_pem
  certificate_chain = tls_self_signed_cert.demo_ca[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-cert"
    Type = "ssl-certificate"
  })
}

# Target Group for Jenkins
resource "aws_lb_target_group" "jenkins" {
  name     = "${var.name_prefix}-jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,403"
    path                = "/login"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-jenkins-tg"
    Type = "target-group"
  })
}

# Note: Nessus target group is created in the Nessus module

# Target Group for App Servers
resource "aws_lb_target_group" "app_servers" {
  name     = "${var.name_prefix}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-app-tg"
    Type = "target-group"
  })
}

# HTTPS Listener (with proper certificate validation dependency)
resource "aws_lb_listener" "https" {
  count = var.domain_name != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.main[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  depends_on = [aws_acm_certificate.main]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-https-listener"
    Type = "lb-listener"
  })
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.domain_name != "" ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.domain_name != "" ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "forward" {
      for_each = var.domain_name == "" ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.jenkins.arn
        }
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-http-listener"
    Type = "lb-listener"
  })
}

# Listener Rules for Jenkins
resource "aws_lb_listener_rule" "jenkins" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  condition {
    path_pattern {
      values = ["/jenkins*"]
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-jenkins-rule"
    Type = "lb-listener-rule"
  })
}

# Nessus ALB Rules - REMOVED: Now using Network Load Balancer with TCP pass-through
# Direct access via NLB on port 8834 eliminates need for HTTP/S proxy rules

# Listener Rules for App Servers
resource "aws_lb_listener_rule" "app_servers" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_servers.arn
  }

  condition {
    path_pattern {
      values = ["/app*"]
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-app-rule"
    Type = "lb-listener-rule"
  })
}

# HTTPS Listener Rules (if domain is configured)
# HTTPS Jenkins Rule
resource "aws_lb_listener_rule" "jenkins_https" {
  count = var.domain_name != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }

  condition {
    path_pattern {
      values = ["/jenkins*"]
    }
  }

  depends_on = [aws_lb_listener.https]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-jenkins-https-rule"
    Type = "lb-listener-rule"
  })
}

# HTTPS Nessus Rule - REMOVED: Using Network Load Balancer with TCP pass-through

# HTTPS App Servers Rule
resource "aws_lb_listener_rule" "app_servers_https" {
  count = var.domain_name != "" ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_servers.arn
  }

  condition {
    path_pattern {
      values = ["/app*"]
    }
  }

  depends_on = [aws_lb_listener.https]

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-app-https-rule"
    Type = "lb-listener-rule"
  })
}

# WAF Association (Optional - for security enhancement)
resource "aws_wafv2_web_acl_association" "main" {
  count = var.enable_waf_association ? 1 : 0

  resource_arn = aws_lb.main.arn
  web_acl_arn  = var.waf_web_acl_arn
}
