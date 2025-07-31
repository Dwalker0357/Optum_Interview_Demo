output "bastion_security_group_id" {
  description = "ID of the bastion security group"
  value       = aws_security_group.bastion.id
}

output "jenkins_security_group_id" {
  description = "ID of the Jenkins security group"
  value       = aws_security_group.jenkins.id
}

output "nessus_security_group_id" {
  description = "ID of the Nessus security group"
  value       = aws_security_group.nessus.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "app_servers_security_group_id" {
  description = "ID of the app servers security group"
  value       = aws_security_group.app_servers.id
}

output "public_network_acl_id" {
  description = "ID of the public network ACL"
  value       = aws_network_acl.public.id
}

output "private_network_acl_id" {
  description = "ID of the private network ACL"
  value       = aws_network_acl.private.id
}

output "security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    bastion = aws_security_group.bastion.id
    jenkins = aws_security_group.jenkins.id
    nessus  = aws_security_group.nessus.id
    alb     = aws_security_group.alb.id
    app     = aws_security_group.app_servers.id
  }
}

# Enhanced Security Groups Outputs
output "enhanced_security_group_ids" {
  description = "Map of enhanced (hardened) security group IDs"
  value = {
    bastion = aws_security_group.bastion_enhanced.id
    jenkins = aws_security_group.jenkins_enhanced.id
    nessus  = aws_security_group.nessus_enhanced.id
    alb     = aws_security_group.alb_enhanced.id
    app     = aws_security_group.app_servers_enhanced.id
  }
}

output "bastion_enhanced_security_group_id" {
  description = "ID of the enhanced bastion security group"
  value       = aws_security_group.bastion_enhanced.id
}

output "jenkins_enhanced_security_group_id" {
  description = "ID of the enhanced Jenkins security group"
  value       = aws_security_group.jenkins_enhanced.id
}

output "nessus_enhanced_security_group_id" {
  description = "ID of the enhanced Nessus security group"
  value       = aws_security_group.nessus_enhanced.id
}

output "alb_enhanced_security_group_id" {
  description = "ID of the enhanced ALB security group"
  value       = aws_security_group.alb_enhanced.id
}

output "app_servers_enhanced_security_group_id" {
  description = "ID of the enhanced app servers security group"
  value       = aws_security_group.app_servers_enhanced.id
}
