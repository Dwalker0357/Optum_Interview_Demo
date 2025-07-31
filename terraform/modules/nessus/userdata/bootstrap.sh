#!/bin/bash
set -e

# Minimal bootstrap script to download and execute the real Nessus init script from S3
# This works around AWS EC2 user-data 16KB limit

# Install AWS CLI if not present (AWS CLI is pre-installed on Amazon Linux 2)
if ! command -v aws &> /dev/null; then
    yum install -y awscli
fi

# Download the real init script from S3
aws s3 cp s3://${s3_bucket}/${script_key} /tmp/nessus-init.sh --region ${aws_region}
chmod +x /tmp/nessus-init.sh

# Execute the real init script with all parameters
export AWS_REGION="${aws_region}"
export S3_BUCKET="${s3_bucket}"
export EFS_ID="${efs_id}"
export SECRET_ARN="${secret_arn}"
export PROJECT_NAME="${project_name}"
export SCAN_SCHEDULE="${scan_schedule}"
export WEBHOOK_URL="${webhook_url}"
export CVE_FEED_ENABLED="${cve_feed_enabled}"
export AUTO_UPDATE_PLUGINS="${auto_update_plugins}"
export NESSUS_VERSION="${NESSUS_VERSION}"

/tmp/nessus-init.sh
