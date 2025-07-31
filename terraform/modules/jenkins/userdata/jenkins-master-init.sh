#!/bin/bash

# Jenkins Master Initialization Script
# This script sets up Jenkins master with EFS storage, plugins, and configuration

set -euo pipefail

# Variables from Terraform
JENKINS_HOME="${jenkins_home}"
JENKINS_USER="${jenkins_user}"
JENKINS_PORT="${jenkins_port}"
AGENT_PORT="${agent_port}"
EFS_ID="${efs_id}"
REGION="${region}"
PROJECT="${project}"
ENVIRONMENT="${environment}"
S3_BUCKET="${s3_bucket}"
SECRETS_ARN="${secrets_arn}"
WEBHOOK_SECRET_ARN="${webhook_secret_arn}"
DEPLOYMENT_MODE="${deployment_mode}"

# Logging setup
exec > >(tee /var/log/jenkins-init.log)
exec 2>&1

echo "=== Jenkins Master Initialization Started ==="
echo "Timestamp: $(date)"
echo "Region: $REGION"
echo "Project: $PROJECT"
echo "Environment: $ENVIRONMENT"
echo "Deployment Mode: $DEPLOYMENT_MODE"

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
    ansible \
    nfs-utils

# Install CloudWatch agent
echo "=== Installing CloudWatch agent ==="
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Create Jenkins user if not exists
if ! id "$JENKINS_USER" &>/dev/null; then
    echo "=== Creating Jenkins user ==="
    useradd -m -s /bin/bash "$JENKINS_USER"
fi

# Add Jenkins user to docker group
usermod -a -G docker "$JENKINS_USER"

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Mount EFS for Jenkins home
echo "=== Setting up EFS mount ==="
mkdir -p "$JENKINS_HOME"

# Create mount point and mount EFS
echo "$EFS_ID.efs.$REGION.amazonaws.com:/ $JENKINS_HOME efs defaults,_netdev" >> /etc/fstab
mount -t efs -o tls "$EFS_ID:/" "$JENKINS_HOME"

# Set ownership
chown -R "$JENKINS_USER:$JENKINS_USER" "$JENKINS_HOME"
chmod 755 "$JENKINS_HOME"

# Install Jenkins
echo "=== Installing Jenkins ==="
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
yum install -y jenkins

# Fix systemd compatibility for Amazon Linux 2 (different issue than 2023)
echo "=== Fixing Jenkins systemd service for Amazon Linux 2 ==="
# Remove problematic StartLimit directives from the Jenkins service file
sudo sed -i '/^StartLimitBurst=/d' /usr/lib/systemd/system/jenkins.service
sudo sed -i '/^StartLimitIntervalSec=/d' /usr/lib/systemd/system/jenkins.service

# Create sysconfig directory and file for Jenkins JAVA_HOME
echo "=== Configuring Jenkins Java environment ==="
mkdir -p /etc/sysconfig
cat > /etc/sysconfig/jenkins << 'JAVA_EOF'
JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto.x86_64
JENKINS_JAVA_CMD=$JAVA_HOME/bin/java
JAVA_EOF

# Set correct Java alternative
echo "=== Setting Java alternative to Java 17 ==="
alternatives --set java /usr/lib/jvm/java-17-amazon-corretto.x86_64/bin/java

# Verify Java 17 installation
echo "=== Verifying Java 17 installation ==="
java -version
if ! java -version 2>&1 | grep -q "17.0"; then
    echo "ERROR: Java 17 not properly installed or configured"
    exit 1
fi
echo "Java 17 verified successfully"

# Install additional development tools (match agent capabilities)
echo "=== Installing development tools ==="

# Install Terraform
wget -q https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_1.6.0_linux_amd64.zip

# Additional tools can be installed here as needed

# Configure Jenkins via systemd override
echo "=== Configuring Jenkins ==="

# Create systemd override for Jenkins configuration
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/jenkins.conf << EOF
[Service]
Environment="JENKINS_HOME=$JENKINS_HOME"
Environment="JENKINS_PORT=$JENKINS_PORT"
Environment="JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto.x86_64"
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xms512m -Xmx2g -XX:+UseG1GC"
Environment="PATH=/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin"
User=$JENKINS_USER
Group=$JENKINS_USER
WorkingDirectory=$JENKINS_HOME
ExecStart=
ExecStart=/usr/lib/jvm/java-17-amazon-corretto.x86_64/bin/java -Djava.awt.headless=true -jar /usr/share/java/jenkins.war --webroot=/var/cache/jenkins/war --httpPort=$JENKINS_PORT
EOF

# Get secrets from Secrets Manager
echo "=== Retrieving secrets from Secrets Manager ==="
JENKINS_SECRETS=$(aws secretsmanager get-secret-value --secret-id "$SECRETS_ARN" --region "$REGION" --query SecretString --output text)
WEBHOOK_SECRETS=$(aws secretsmanager get-secret-value --secret-id "$WEBHOOK_SECRET_ARN" --region "$REGION" --query SecretString --output text)

# Extract credentials
JENKINS_ADMIN_PASSWORD=$(echo "$JENKINS_SECRETS" | jq -r '.admin_password')
GITHUB_TOKEN=$(echo "$JENKINS_SECRETS" | jq -r '.github_token')
AWS_ACCESS_KEY=$(echo "$JENKINS_SECRETS" | jq -r '.aws_access_key')
AWS_SECRET_KEY=$(echo "$JENKINS_SECRETS" | jq -r '.aws_secret_key')

NESSUS_URL=$(echo "$WEBHOOK_SECRETS" | jq -r '.nessus_url')
NESSUS_ACCESS_KEY=$(echo "$WEBHOOK_SECRETS" | jq -r '.access_key')
NESSUS_SECRET_KEY=$(echo "$WEBHOOK_SECRETS" | jq -r '.secret_key')

# Setup Jenkins directories
echo "=== Setting up Jenkins directories ==="
mkdir -p "$JENKINS_HOME"/{init.groovy.d,plugins,jobs,secrets,logs,workspace,tools}
chown -R "$JENKINS_USER:$JENKINS_USER" "$JENKINS_HOME"

# Skip initial setup wizard
echo "=== Configuring Jenkins startup ==="
echo "2.426.3" > "$JENKINS_HOME/jenkins.install.InstallUtil.lastExecVersion"
echo "2.426.3" > "$JENKINS_HOME/jenkins.install.UpgradeWizard.state"

# Create initial admin user setup script
cat > "$JENKINS_HOME/init.groovy.d/01-create-admin-user.groovy" << 'GROOVY_EOF'
#!groovy
import jenkins.model.*
import hudson.security.*
import hudson.security.csrf.DefaultCrumbIssuer
import jenkins.security.s2m.AdminWhitelistRule

def instance = Jenkins.getInstance()

// Create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", System.getenv("JENKINS_ADMIN_PASSWORD"))
instance.setSecurityRealm(hudsonRealm)

// Set authorization strategy
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// Enable CSRF protection
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// Enable agent to master security
instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)

instance.save()
println "Admin user created successfully"
GROOVY_EOF

# Create Jenkins configuration script
cat > "$JENKINS_HOME/init.groovy.d/02-configure-jenkins.groovy" << 'GROOVY_EOF'
#!groovy
import jenkins.model.*
import hudson.model.*
import hudson.slaves.*
import hudson.slaves.EnvironmentVariablesNodeProperty.Entry
import hudson.plugins.ec2.*
import com.amazonaws.services.ec2.model.InstanceType
import hudson.tools.*

def instance = Jenkins.getInstance()

// Set global properties
def globalNodeProperties = instance.getGlobalNodeProperties()
def envVarsNodePropertyList = globalNodeProperties.getAll(EnvironmentVariablesNodeProperty.class)

def newEnvVarsNodeProperty = null
def envVars = null

if (envVarsNodePropertyList == null || envVarsNodePropertyList.size() == 0) {
  newEnvVarsNodeProperty = new EnvironmentVariablesNodeProperty();
  globalNodeProperties.add(newEnvVarsNodeProperty)
  envVars = newEnvVarsNodeProperty.getEnvVars()
} else {
  envVars = envVarsNodePropertyList.get(0).getEnvVars()
}

// Set environment variables
envVars.put("AWS_DEFAULT_REGION", System.getenv("REGION"))
envVars.put("PROJECT_NAME", System.getenv("PROJECT"))
envVars.put("ENVIRONMENT", System.getenv("ENVIRONMENT"))
envVars.put("S3_ARTIFACTS_BUCKET", System.getenv("S3_BUCKET"))
envVars.put("PATH", "/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin")

// Configure number of executors on master
instance.setNumExecutors(2)

// Configure Jenkins URL
def jlc = JenkinsLocationConfiguration.get()
jlc.setUrl("http://jenkins.$${System.getenv("ENVIRONMENT")}.internal:8080/")
jlc.setAdminAddress("admin@$${System.getenv("PROJECT")}.com")
jlc.save()

instance.save()
println "Jenkins configuration completed"
GROOVY_EOF

# Create AWS credentials configuration
cat > "$JENKINS_HOME/init.groovy.d/03-configure-aws-credentials.groovy" << 'GROOVY_EOF'
#!groovy
import jenkins.model.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.jenkins.plugins.awscredentials.AWSCredentialsImpl
import hudson.util.Secret

def instance = Jenkins.getInstance()
def domain = Domain.global()
def store = instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()

// Create AWS credentials
def awsCredentials = new AWSCredentialsImpl(
    CredentialsScope.GLOBAL,
    "aws-credentials",
    System.getenv("AWS_ACCESS_KEY"),
    System.getenv("AWS_SECRET_KEY"),
    "AWS Credentials for Jenkins"
)

store.addCredentials(domain, awsCredentials)

// Create GitHub token
def githubCredentials = new org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "github-token",
    "GitHub Personal Access Token",
    Secret.fromString(System.getenv("GITHUB_TOKEN"))
)

store.addCredentials(domain, githubCredentials)

instance.save()
println "AWS and GitHub credentials configured"
GROOVY_EOF

# Create EC2 cloud configuration
cat > "$JENKINS_HOME/init.groovy.d/04-configure-ec2-cloud.groovy" << 'GROOVY_EOF'
#!groovy
import jenkins.model.*
import hudson.plugins.ec2.*
import com.amazonaws.services.ec2.model.InstanceType

def instance = Jenkins.getInstance()

// EC2 Cloud configuration
def ec2Cloud = new AmazonEC2Cloud(
    "aws-cloud",
    true,
    "aws-credentials",
    System.getenv("REGION"),
    "",
    "",
    10,
    3,
    30
)

// Create AMI configuration for agents
def amiConfig = new SlaveTemplate(
    "$${System.getenv("REGION")}:ami-0abcdef1234567890", // Will be updated by launch template
    "us-west-2a",
    null,
    "jenkins-agent",
    "$${System.getenv("PROJECT")}-jenkins-agent",
    InstanceType.T3Micro.toString(),
    false,
    "jenkins-agent",
    Node.Mode.NORMAL,
    "linux docker ansible aws",
    "/tmp",
    null,
    "-Xmx1024m",
    1,
    1,
    "jenkins-agent",
    "22",
    "",
    "",
    true,
    false,
    "",
    "",
    true,
    true,
    "",
    null,
    null,
    0,
    null,
    null,
    UnixData(),
    null,
    null,
    false,
    false,
    null,
    null,
    false,
    ConnectionStrategy.PRIVATE_IP,
    30,
    null
)

ec2Cloud.addTemplate(amiConfig)
instance.clouds.add(ec2Cloud)

instance.save()
println "EC2 Cloud configuration completed"
GROOVY_EOF

# Create pipeline job configuration
cat > "$JENKINS_HOME/init.groovy.d/05-create-seed-jobs.groovy" << 'GROOVY_EOF'
#!groovy
import jenkins.model.*
import hudson.model.*
import javaposse.jobdsl.plugin.*

def instance = Jenkins.getInstance()

// Create Infrastructure Provisioning Pipeline
def infraJob = instance.createProject(FreeStyleProject, "infrastructure-provisioning-seed")
infraJob.setDescription("Seed job for infrastructure provisioning pipelines")

// Create Security Scanning Pipeline
def securityJob = instance.createProject(FreeStyleProject, "security-scanning-seed")
securityJob.setDescription("Seed job for security scanning pipelines")

// Create Application Deployment Pipeline
def appJob = instance.createProject(FreeStyleProject, "application-deployment-seed")
appJob.setDescription("Seed job for application deployment pipelines")

instance.save()
println "Seed jobs created successfully"
GROOVY_EOF

# Create Nessus webhook configuration
cat > "$JENKINS_HOME/init.groovy.d/06-configure-nessus-webhook.groovy" << 'GROOVY_EOF'
#!groovy
import jenkins.model.*
import hudson.model.*

def instance = Jenkins.getInstance()

// Create Nessus webhook job
def nessusJob = instance.createProject(FreeStyleProject, "nessus-webhook-handler")
nessusJob.setDescription("Handles Nessus scan completion webhooks")

// Configure webhook URL in global properties
def globalNodeProperties = instance.getGlobalNodeProperties()
def envVarsNodePropertyList = globalNodeProperties.getAll(EnvironmentVariablesNodeProperty.class)

if (envVarsNodePropertyList.size() > 0) {
    def envVars = envVarsNodePropertyList.get(0).getEnvVars()
    envVars.put("NESSUS_URL", System.getenv("NESSUS_URL"))
    envVars.put("NESSUS_ACCESS_KEY", System.getenv("NESSUS_ACCESS_KEY"))
    envVars.put("NESSUS_SECRET_KEY", System.getenv("NESSUS_SECRET_KEY"))
}

instance.save()
println "Nessus webhook configuration completed"
GROOVY_EOF

# Set environment variables for init scripts
export JENKINS_ADMIN_PASSWORD="$JENKINS_ADMIN_PASSWORD"
export GITHUB_TOKEN="$GITHUB_TOKEN"
export AWS_ACCESS_KEY="$AWS_ACCESS_KEY"
export AWS_SECRET_KEY="$AWS_SECRET_KEY"
export NESSUS_URL="$NESSUS_URL"
export NESSUS_ACCESS_KEY="$NESSUS_ACCESS_KEY"
export NESSUS_SECRET_KEY="$NESSUS_SECRET_KEY"
export REGION="$REGION"
export PROJECT="$PROJECT"
export ENVIRONMENT="$ENVIRONMENT"
export S3_BUCKET="$S3_BUCKET"

# Install Jenkins plugins
echo "=== Installing Jenkins plugins ==="
mkdir -p "$JENKINS_HOME/plugins"

# Plugin list - use space-separated string instead of array for Terraform compatibility
PLUGINS="ant:475.vf34069fef73c antisamy-markup-formatter:159.v25b_c67cd35fb_ build-timeout:1.31 credentials-binding:523.vd859a_4b_122e6 timestamper:1.25 ws-cleanup:0.45 github:1.37.3.1 github-branch-source:1703.vd5a_2b_29c6cdc pipeline-github-lib:42.v0739460cda_c4 pipeline-stage-view:2.25 git:5.0.0 ssh-slaves:2.916.vd4c3d4a_da_478 matrix-auth:3.1.10 pam-auth:1.10 ldap:682.v7b_544c9d1512 email-ext:2.96 mailer:463.vedf8358e006b_ slack:664.vc9a_90f8b_c24a_ ansible:403.v8d0ca_dcb_b_502 ec2:2.0.6 aws-credentials:191.vcb_f183ce58b_9 s3:0.12.0 pipeline-aws:1.43 docker-workflow:572.v950f58993843 blueocean:1.27.3 prometheus:2.2.3 monitoring:1.98.0"

# Download and install plugins
for plugin in $PLUGINS; do
    plugin_name=$(echo "$plugin" | cut -d: -f1)
    plugin_version=$(echo "$plugin" | cut -d: -f2)
    echo "Installing plugin: $plugin_name:$plugin_version"
    
    wget -q "https://updates.jenkins.io/download/plugins/$plugin_name/$plugin_version/$plugin_name.hpi" \
        -O "$JENKINS_HOME/plugins/$plugin_name.jpi" || echo "Failed to download $plugin_name"
done

# Set plugin ownership
chown -R "$JENKINS_USER:$JENKINS_USER" "$JENKINS_HOME/plugins"

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
                        "file_path": "/var/log/jenkins/jenkins.log",
                        "log_group_name": "/aws/ec2/jenkins/$PROJECT",
                        "log_stream_name": "{instance_id}/jenkins.log"
                    },
                    {
                        "file_path": "/var/log/jenkins-init.log",
                        "log_group_name": "/aws/ec2/jenkins/$PROJECT",
                        "log_stream_name": "{instance_id}/init.log"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Jenkins/Master",
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

# Create Jenkins backup script
echo "=== Creating backup script ==="
cat > /usr/local/bin/jenkins-backup.sh << 'BACKUP_EOF'
#!/bin/bash

# Jenkins Backup Script
JENKINS_HOME="${jenkins_home}"
S3_BUCKET="${s3_bucket}"
REGION="${region}"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="jenkins-backup-$DATE.tar.gz"

echo "Starting Jenkins backup: $DATE"

# Stop Jenkins temporarily
systemctl stop jenkins

# Create backup
cd /tmp
tar -czf "$BACKUP_NAME" \
    --exclude="$JENKINS_HOME/workspace" \
    --exclude="$JENKINS_HOME/logs" \
    --exclude="$JENKINS_HOME/caches" \
    "$JENKINS_HOME"

# Upload to S3
aws s3 cp "$BACKUP_NAME" "s3://$S3_BUCKET/backups/" --region "$REGION"

# Cleanup local backup
rm -f "$BACKUP_NAME"

# Start Jenkins
systemctl start jenkins

echo "Backup completed: $BACKUP_NAME"
BACKUP_EOF

chmod +x /usr/local/bin/jenkins-backup.sh

# Create cron job for backups (if enabled)
if [ "$DEPLOYMENT_MODE" == "full" ]; then
    echo "0 3 * * * root /usr/local/bin/jenkins-backup.sh >> /var/log/jenkins-backup.log 2>&1" >> /etc/crontab
fi

# Install additional tools BEFORE starting Jenkins
echo "=== Installing additional tools ==="

# Install latest Terraform
echo "Installing Terraform..."
TERRAFORM_VERSION="${terraform_version}"
wget -q https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
unzip terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
mv terraform /usr/local/bin/
rm terraform_$${TERRAFORM_VERSION}_linux_amd64.zip
terraform --version

# kubectl and helm removed - not needed for AWS infrastructure demo

# Make tools executable
chmod +x /usr/local/bin/terraform

# Verify tools are installed and accessible
echo "=== Verifying tool installations ==="
echo "Terraform version:"
/usr/local/bin/terraform --version

# Set final ownership
chown -R "$JENKINS_USER:$JENKINS_USER" "$JENKINS_HOME"

# Start and enable Jenkins
echo "=== Starting Jenkins service ==="
systemctl daemon-reload
systemctl start jenkins
systemctl enable jenkins

# Wait for Jenkins to start
echo "=== Waiting for Jenkins to start ==="
timeout=600
counter=0
while ! curl -f -s "http://localhost:$JENKINS_PORT/login" > /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo "ERROR: Jenkins failed to start within $timeout seconds"
        echo "Jenkins service status:"
        systemctl status jenkins --no-pager
        echo "Recent Jenkins logs:"
        journalctl -u jenkins --since "5 min ago" --no-pager
        exit 1
    fi
    echo "Waiting for Jenkins to start... ($counter/$timeout)"
    sleep 15
    counter=$((counter + 15))
done

echo "=== Jenkins started successfully ==="

# Additional verification that Jenkins is responding properly
echo "=== Verifying Jenkins HTTP response ==="
response=$(curl -s -o /dev/null -w "%%{http_code}" "http://localhost:$JENKINS_PORT/login")
if [ "$response" != "200" ]; then
    echo "WARNING: Jenkins returned HTTP $response instead of 200"
    echo "Jenkins may still be initializing. Continuing..."
fi

# Verify Jenkins can access tools
echo "=== Verifying Jenkins can access required tools ==="
sudo -u jenkins bash -c "PATH=/usr/local/bin:\$PATH terraform --version" || echo "WARNING: Jenkins cannot access terraform"
# kubectl and helm removed - not needed for AWS infrastructure demo

echo "=== Final system status check ==="
systemctl status jenkins --no-pager

echo "=== Jenkins Master Initialization Completed Successfully ==="
echo "Jenkins URL: http://localhost:$JENKINS_PORT"
echo "Admin user: admin"
echo "Check status: systemctl status jenkins"
echo "View logs: tail -f /var/log/jenkins/jenkins.log"
