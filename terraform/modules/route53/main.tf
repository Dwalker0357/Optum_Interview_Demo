# Route53 DNS Module
# Creates public or private hosted zone for DNS resolution

resource "aws_route53_zone" "main" {
  name = var.domain_name

  # Only add VPC associations for private zones
  dynamic "vpc" {
    for_each = var.private_zone ? var.vpc_configs : {}
    content {
      vpc_id     = vpc.value.vpc_id
      vpc_region = vpc.value.region
    }
  }

  tags = merge(var.tags, {
    Type = var.private_zone ? "Private" : "Public"
  })
}

# DNS records for services are created as separate resources to avoid circular dependencies
