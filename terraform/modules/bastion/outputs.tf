output "bastion_launch_template_id" {
  description = "ID of the bastion launch template"
  value       = aws_launch_template.bastion.id
}

output "bastion_asg_name" {
  description = "Name of the bastion Auto Scaling Group"
  value       = aws_autoscaling_group.bastion.name
}

output "bastion_iam_role_arn" {
  description = "ARN of the bastion IAM role"
  value       = var.bastion_role_arn
}

output "bastion_iam_role_name" {
  description = "Name of the bastion IAM role"
  value       = var.bastion_role_arn
}

output "bastion_instance_profile_name" {
  description = "Name of the bastion instance profile"
  value       = var.bastion_instance_profile
}

output "bastion_eip_public_ip" {
  description = "Public IP of the bastion Elastic IP (if created)"
  value       = var.create_eip ? aws_eip.bastion[0].public_ip : ""
}

output "bastion_eip_allocation_id" {
  description = "Allocation ID of the bastion Elastic IP (if created)"
  value       = var.create_eip ? aws_eip.bastion[0].allocation_id : ""
}

output "bastion_cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for bastion"
  value       = aws_cloudwatch_log_group.bastion.name
}

output "ssh_command" {
  description = "SSH command to connect to bastion (when EIP is created)"
  value       = var.create_eip ? "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_eip.bastion[0].public_ip}" : "Use ASG to get instance IP"
}

output "session_manager_command" {
  description = "AWS CLI command to start Session Manager session"
  value       = "aws ssm start-session --target <instance-id>"
}

output "connection_info" {
  description = "Information for connecting to the bastion host"
  value = {
    ssh_key_required = var.key_pair_name
    public_ip        = var.create_eip ? aws_eip.bastion[0].public_ip : "Dynamic (check ASG instances)"
    session_manager  = "Available via AWS CLI"
    cloudwatch_logs  = aws_cloudwatch_log_group.bastion.name
  }
}
