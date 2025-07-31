output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "jenkins_target_group_arn" {
  description = "ARN of the Jenkins target group"
  value       = aws_lb_target_group.jenkins.arn
}

# nessus_target_group_arn output removed - using Network Load Balancer instead

output "app_servers_target_group_arn" {
  description = "ARN of the app servers target group"
  value       = aws_lb_target_group.app_servers.arn
}

output "ssl_certificate_arn" {
  description = "ARN of the SSL certificate (if created)"
  value       = var.domain_name != "" ? aws_acm_certificate.main[0].arn : ""
}

output "jenkins_url" {
  description = "URL to access Jenkins through ALB"
  value       = var.domain_name != "" ? "https://${var.domain_name}/jenkins" : "http://${aws_lb.main.dns_name}/jenkins"
}

output "nessus_url" {
  description = "URL to access Nessus through ALB (DEPRECATED - use Nessus NLB instead)"
  value       = "DEPRECATED: Use Nessus module output 'nessus_url' for direct NLB access"
}

output "app_url" {
  description = "URL to access application through ALB"
  value       = var.domain_name != "" ? "https://${var.domain_name}/app" : "http://${aws_lb.main.dns_name}/app"
}

output "target_group_arns" {
  description = "Map of all target group ARNs"
  value = {
    jenkins     = aws_lb_target_group.jenkins.arn
    app_servers = aws_lb_target_group.app_servers.arn
    # nessus removed - using Network Load Balancer instead
  }
}
