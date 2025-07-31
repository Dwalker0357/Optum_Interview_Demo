#!/bin/bash

# Jenkins Agent Initialization Script
# This script sets up Jenkins agents with Docker, Ansible, AWS CLI, and auto-connection to master

set -euo pipefail

# Variables from Terraform
JENKINS_MASTER_URL="${jenkins_master_url}"
JENKINS_USER="${jenkins_user}"
REGION="${region}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
S3_BUCKET="${s3_bucket}"
SECRETS_ARN="${secrets_arn}"
EFS_FILE_SYSTEM_ID="${efs_file_system_id}"

# Logging setup
exec > >(tee /var/log/jenkins-agent-init.log)
exec 2>&1

echo "=== Jenkins Agent Initialization Started ==="
echo "Timestamp: $(date)"
echo "Region: $REGION"
echo "Project: $PROJECT"
echo "Environment: $ENVIRONMENT"
echo "Jenkins Master URL: $JENKINS_MASTER_URL"

# Update system
echo "=== Updating system packages ==="
yum update -y

# Install dependencies
echo "=== Installing required packages ==="
yum install -y \
    java-17-amazon-corretto \
    wget \
    git \
    amazon-efs-utils \
    awscli \
    jq \
    curl \
    unzip \
    docker \
    python3 \
    python3-pip \
    gcc \
    gcc-c++ \
    make \
    openssl-devel \
    libffi-devel \
    python3-devel

# Install CloudWatch agent
echo "=== Installing CloudWatch agent ==="
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Install Ansible
echo "=== Installing Ansible ==="
pip3 install --upgrade pip
pip3 install ansible boto3 botocore

# Create Jenkins user
echo "=== Creating Jenkins user ==="
if ! id "$JENKINS_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$JENKINS_USER"
fi

# Add Jenkins user to docker group
usermod -a -G docker "$JENKINS_USER"

# Start and enable Docker
echo "=== Starting Docker service ==="
systemctl start docker
systemctl enable docker

# Install Docker Compose
echo "=== Installing Docker Compose ==="
curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install additional development tools
echo "=== Installing development tools ==="

# Install Terraform
wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_1.6.0_linux_amd64.zip

# Additional tools can be installed here as needed

# Install Node.js and npm
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Install Python packages
echo "=== Installing Python packages ==="
pip3 install \
    boto3 \
    botocore \
    awscli \
    ansible \
    requests \
    pyyaml \
    jinja2 \
    netaddr \
    python-jenkins \
    docker

# Mount EFS for shared workspace
echo "=== Mounting EFS file system ==="
mkdir -p /mnt/jenkins-shared
echo "$EFS_FILE_SYSTEM_ID.efs.$REGION.amazonaws.com:/ /mnt/jenkins-shared efs defaults,_netdev" >> /etc/fstab
mount -t efs -o tls "$EFS_FILE_SYSTEM_ID:/" /mnt/jenkins-shared

# Configure Jenkins agent workspace
echo "=== Setting up Jenkins agent workspace ==="
AGENT_HOME="/home/$JENKINS_USER"
mkdir -p "$AGENT_HOME"/{workspace,tools,tmp}
mkdir -p /mnt/jenkins-shared/agents/$(hostname)
ln -sf /mnt/jenkins-shared/agents/$(hostname) "$AGENT_HOME/shared-workspace"
chown -R "$JENKINS_USER:$JENKINS_USER" "$AGENT_HOME"
chown -R "$JENKINS_USER:$JENKINS_USER" /mnt/jenkins-shared/agents/$(hostname)

# Get secrets from Secrets Manager
echo "=== Retrieving secrets from Secrets Manager ==="
JENKINS_SECRETS=$(aws secretsmanager get-secret-value --secret-id "$SECRETS_ARN" --region "$REGION" --query SecretString --output text)

# Extract credentials
AWS_ACCESS_KEY=$(echo "$JENKINS_SECRETS" | jq -r '.aws_access_key')
AWS_SECRET_KEY=$(echo "$JENKINS_SECRETS" | jq -r '.aws_secret_key')

# Configure AWS CLI for Jenkins user
echo "=== Configuring AWS CLI ==="
su - "$JENKINS_USER" -c "
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY
aws_secret_access_key = $AWS_SECRET_KEY
EOF

cat > ~/.aws/config << EOF
[default]
region = $REGION
output = json
EOF
"

# Install Jenkins Swarm client
echo "=== Installing Jenkins Swarm client ==="
SWARM_VERSION="3.29"
wget "https://repo.jenkins-ci.org/releases/org/jenkins-ci/plugins/swarm-client/$SWARM_VERSION/swarm-client-$SWARM_VERSION.jar" \
    -O /opt/swarm-client.jar

# Create Jenkins agent service script
cat > /usr/local/bin/jenkins-agent.sh << 'AGENT_EOF'
#!/bin/bash

JENKINS_USER="${jenkins_user}"
JENKINS_MASTER_URL="${jenkins_master_url}"
AGENT_NAME="agent-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
SWARM_JAR="/opt/swarm-client.jar"

# Get Jenkins credentials from secrets
SECRETS=$(aws secretsmanager get-secret-value --secret-id "${secrets_arn}" --region "${region}" --query SecretString --output text)
JENKINS_USERNAME=$(echo "$SECRETS" | jq -r '.admin_username // "admin"')
JENKINS_PASSWORD=$(echo "$SECRETS" | jq -r '.admin_password')

echo "Starting Jenkins agent: $AGENT_NAME"
echo "Connecting to: $JENKINS_MASTER_URL"

# Wait for Jenkins master to be available
timeout=600
counter=0
while ! curl -f -s "$JENKINS_MASTER_URL/login" > /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo "ERROR: Jenkins master not available after $timeout seconds"
        exit 1
    fi
    echo "Waiting for Jenkins master... ($counter/$timeout)"
    sleep 10
    counter=$((counter + 10))
done

# Start swarm agent
exec java -jar "$SWARM_JAR" \
    -master "$JENKINS_MASTER_URL" \
    -username "$JENKINS_USERNAME" \
    -password "$JENKINS_PASSWORD" \
    -name "$AGENT_NAME" \
    -description "Auto-provisioned Jenkins agent" \
    -labels "linux docker ansible aws terraform" \
    -mode normal \
    -executors 2 \
    -fsroot "/home/$JENKINS_USER/workspace" \
    -disableClientsUniqueId \
    -deleteExistingClients
AGENT_EOF

chmod +x /usr/local/bin/jenkins-agent.sh

# Create systemd service for Jenkins agent
cat > /etc/systemd/system/jenkins-agent.service << EOF
[Unit]
Description=Jenkins Swarm Agent
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$JENKINS_USER
Group=$JENKINS_USER
ExecStart=/usr/local/bin/jenkins-agent.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configure CloudWatch agent
echo "=== Configuring CloudWatch agent ==="
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
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
                        "file_path": "/var/log/jenkins-agent-init.log",
                        "log_group_name": "/aws/ec2/jenkins/$PROJECT",
                        "log_stream_name": "{instance_id}/agent-init.log"
                    },
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/jenkins/$PROJECT",
                        "log_stream_name": "{instance_id}/messages"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Jenkins/Agents",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "diskio": {
                "measurement": ["io_time"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
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
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Create workspace directories
echo "=== Setting up workspace directories ==="
su - "$JENKINS_USER" -c "
mkdir -p ~/workspace/{infrastructure,security,applications}
mkdir -p ~/tools/{terraform,ansible,docker}
mkdir -p ~/bin
"

# Create tool symbolic links for Jenkins user
su - "$JENKINS_USER" -c "
ln -sf /usr/local/bin/terraform ~/bin/
ln -sf /usr/local/bin/docker-compose ~/bin/
ln -sf /usr/bin/ansible ~/bin/
ln -sf /usr/bin/ansible-playbook ~/bin/
"

# Configure Docker for Jenkins user
echo "=== Configuring Docker for Jenkins user ==="
su - "$JENKINS_USER" -c "
# Test Docker access
docker --version
docker-compose --version

# Pull common Docker images
docker pull alpine:latest
docker pull ubuntu:latest
docker pull python:3.9-slim
docker pull node:18-alpine
docker pull nginx:alpine
"

# Install additional Ansible collections
echo "=== Installing Ansible collections ==="
su - "$JENKINS_USER" -c "
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install community.general
ansible-galaxy collection install community.docker
# Kubernetes collection not needed for this project
"

# Create Ansible configuration
su - "$JENKINS_USER" -c "
mkdir -p ~/.ansible
cat > ~/.ansible/ansible.cfg << 'ANSIBLE_EOF'
[defaults]
host_key_checking = False
stdout_callback = yaml
inventory = ~/workspace/inventory
roles_path = ~/workspace/roles
collections_paths = ~/.ansible/collections
retry_files_enabled = False
log_path = ~/workspace/ansible.log

[inventory]
enable_plugins = aws_ec2, auto

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
ANSIBLE_EOF
"

# Install and configure security tools
echo "=== Installing security tools ==="

# Install Nessus scanner client tools (if available)
pip3 install tenable-io

# Install security scanning tools
yum install -y nmap nikto

# Configure environment variables
echo "=== Setting up environment variables ==="
cat >> /home/$JENKINS_USER/.bashrc << 'ENV_EOF'
# Jenkins Agent Environment
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
export PATH=$PATH:$JAVA_HOME/bin:/home/jenkins/bin
export AWS_DEFAULT_REGION=${region}
export PROJECT_NAME=${project}
export ENVIRONMENT=${environment}
export S3_ARTIFACTS_BUCKET=${s3_bucket}

# Tool configurations
export TERRAFORM_LOG_PATH=/home/jenkins/workspace/terraform.log
export ANSIBLE_LOG_PATH=/home/jenkins/workspace/ansible.log
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# AWS CLI configuration
export AWS_CLI_AUTO_PROMPT=on-partial
ENV_EOF

chown jenkins:jenkins /home/$JENKINS_USER/.bashrc

# Create health check script
cat > /usr/local/bin/agent-health-check.sh << 'HEALTH_EOF'
#!/bin/bash

# Jenkins Agent Health Check
echo "=== Jenkins Agent Health Check ==="
echo "Timestamp: $(date)"

# Check if Jenkins agent service is running
if systemctl is-active --quiet jenkins-agent; then
    echo "✓ Jenkins agent service is running"
else
    echo "✗ Jenkins agent service is not running"
    systemctl status jenkins-agent
    exit 1
fi

# Check Docker
if docker ps > /dev/null 2>&1; then
    echo "✓ Docker is working"
else
    echo "✗ Docker is not working"
    exit 1
fi

# Check AWS CLI
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo "✓ AWS CLI is configured"
else
    echo "✗ AWS CLI is not configured"
    exit 1
fi

# Check Ansible
if ansible --version > /dev/null 2>&1; then
    echo "✓ Ansible is installed"
else
    echo "✗ Ansible is not installed"
    exit 1
fi

# Check Terraform
if terraform version > /dev/null 2>&1; then
    echo "✓ Terraform is installed"
else
    echo "✗ Terraform is not installed"
    exit 1
fi

echo "=== All health checks passed ==="
HEALTH_EOF

chmod +x /usr/local/bin/agent-health-check.sh

# Set up cron job for health checks
echo "*/5 * * * * root /usr/local/bin/agent-health-check.sh >> /var/log/agent-health.log 2>&1" >> /etc/crontab

# Start and enable services
echo "=== Starting services ==="
systemctl daemon-reload
systemctl enable jenkins-agent
systemctl start jenkins-agent

# Final ownership fixes
chown -R "$JENKINS_USER:$JENKINS_USER" "/home/$JENKINS_USER"

echo "=== Jenkins Agent Initialization Completed Successfully ==="
echo "Agent will automatically connect to: $JENKINS_MASTER_URL"
echo "Check agent status: systemctl status jenkins-agent"
echo "View agent logs: journalctl -u jenkins-agent -f"
echo "Run health check: /usr/local/bin/agent-health-check.sh"

# Signal successful completion
echo "Jenkins agent initialization completed at $(date)" > /tmp/jenkins-agent-ready
