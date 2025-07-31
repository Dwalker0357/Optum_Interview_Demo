#!/bin/bash

# Update system
yum update -y

# Install required packages
yum install -y \
    awscli \
    htop \
    tree \
    wget \
    curl \
    git \
    vim \
    tmux \
    jq

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Session Manager plugin
yum install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/bastion/${aws_region}",
                        "log_stream_name": "{instance_id}/messages"
                    },
                    {
                        "file_path": "/var/log/secure",
                        "log_group_name": "/aws/ec2/bastion/${aws_region}",
                        "log_stream_name": "{instance_id}/secure"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "CWAgent",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Configure & harden SSH daemon
SSH_CFG="/etc/ssh/sshd_config"

# One-time backup
cp -n ${SSH_CFG}{,.orig}

# Enforce secure settings (edit in place if the directive exists,
# append if it does not - avoids duplicate lines piling up on re-runs)
apply_sshd () {
    local key="$1" value="$2"
    if grep -qE "^[# ]*${key}" "${SSH_CFG}"; then
        sed -i "s|^[# ]*${key}.*|${key} ${value}|" "${SSH_CFG}"
    else
        echo "${key} ${value}" >> "${SSH_CFG}"
    fi
}

apply_sshd PermitRootLogin              "no"        # disable root SSH entirely
apply_sshd PasswordAuthentication       "no"        # disable password auth
apply_sshd ChallengeResponseAuthentication "no"     # disable keyboard-interactive / PAM passwords
apply_sshd ClientAliveInterval          "60"        # (existing value, idempotent)
apply_sshd ClientAliveCountMax          "3"         # (existing value, idempotent)

# Extra but safe bastion hardening
apply_sshd X11Forwarding                "no"
apply_sshd UseDNS                       "no"
apply_sshd MaxAuthTries                 "3"
apply_sshd LoginGraceTime               "30"

systemctl restart sshd

# Create motd
cat > /etc/motd << 'EOF'
#################################################################
#                   Optum UK Demo - Bastion Host              #
#################################################################
#                                                               #
# This is a bastion host for the Optum UK Demo environment.   #
# All connections are logged and monitored.                    #
#                                                               #
# Available tools:                                              #
# - AWS CLI v2                                                  #
# - Session Manager                                             #
# - Standard Linux utilities                                    #
#                                                               #
# To connect to private instances:                             #
# - Use Session Manager: aws ssm start-session --target <id>  #
# - Use SSH with port forwarding                              #
#                                                               #
#################################################################
EOF

# Set up useful aliases
cat > /etc/profile.d/bastion-aliases.sh << 'EOF'
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias instances='aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress,Tags[?Key==\`Name\`].Value|[0]]" --output table'
alias ssm-start='aws ssm start-session --target'
EOF

# Configure instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)

# Set hostname
hostnamectl set-hostname "bastion-$INSTANCE_ID"

# Associate Elastic IP if configured
EIP_ALLOCATION_ID=$(aws ssm get-parameter --name "/${aws_region}/bastion/eip-allocation-id" --region ${aws_region} --query 'Parameter.Value' --output text 2>/dev/null || echo "")
if [ -n "$EIP_ALLOCATION_ID" ] && [ "$EIP_ALLOCATION_ID" != "None" ]; then
    aws ec2 associate-address --instance-id $INSTANCE_ID --allocation-id $EIP_ALLOCATION_ID --region ${aws_region}
fi

# Signal CloudFormation (if this was launched via CloudFormation)
# This is optional and won't cause issues if not in a CF context
/opt/aws/bin/cfn-signal -e $? --stack ${aws_region} --resource AutoScalingGroup --region ${aws_region} || true

# Setup log rotation for SSH logs
cat > /etc/logrotate.d/ssh-logs << 'EOF'
/var/log/secure {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}
EOF

echo "Bastion host setup completed at $(date)" >> /var/log/user-data.log
