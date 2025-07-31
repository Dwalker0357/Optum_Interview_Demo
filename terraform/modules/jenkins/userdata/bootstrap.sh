#!/bin/bash
set -e

# Minimal bootstrap script to download and execute the real init script from S3
# This works around AWS EC2 user-data 16KB limit

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    yum update -y
    yum install -y awscli
fi

# Download the real init script from S3
aws s3 cp s3://${s3_bucket}/${script_key} /tmp/init.sh --region ${region}
chmod +x /tmp/init.sh

# Set environment variables for the real init script
export JENKINS_HOME="${jenkins_home}"
export JENKINS_USER="${jenkins_user}"
export JENKINS_PORT="${jenkins_port}"
export AGENT_PORT="${agent_port}"
export EFS_ID="${efs_id}"
export AWS_DEFAULT_REGION="${region}"
export PROJECT="${project}"
export ENVIRONMENT="${environment}"
export S3_BUCKET="${s3_bucket}"
export SECRETS_ARN="${secrets_arn}"
export WEBHOOK_SECRET_ARN="${webhook_secret_arn}"
export DEPLOYMENT_MODE="${deployment_mode}"

# Optional variables (only set if provided)
%{ if jenkins_master_url != "" ~}
export JENKINS_MASTER_URL="${jenkins_master_url}"
%{ endif ~}
%{ if efs_file_system_id != "" ~}
export EFS_FILE_SYSTEM_ID="${efs_file_system_id}"
%{ endif ~}

# Execute the real init script
/tmp/init.sh
