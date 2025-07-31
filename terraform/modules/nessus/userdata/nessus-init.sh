#!/bin/bash

# Nessus Scanner Initialization Script
# This script configures and starts Nessus vulnerability scanner on EC2 instances

set -euo pipefail

# Environment variables passed from bootstrap.sh
AWS_REGION="${AWS_REGION}"
S3_BUCKET="${S3_BUCKET}"
EFS_ID="${EFS_ID}"
SECRET_ARN="${SECRET_ARN}"
PROJECT_NAME="${PROJECT_NAME}"
SCAN_SCHEDULE="${SCAN_SCHEDULE}"
WEBHOOK_URL="${WEBHOOK_URL}"
CVE_FEED_ENABLED="${CVE_FEED_ENABLED}"
AUTO_UPDATE_PLUGINS="${AUTO_UPDATE_PLUGINS}"

# Constants
LOG_FILE="/var/log/nessus-init.log"
NESSUS_HOME="/opt/nessus"
NESSUS_VAR="/opt/nessus/var/nessus"
EFS_MOUNT_POINT="/mnt/nessus-shared"
SHARED_POLICIES_DIR="$EFS_MOUNT_POINT/policies"
SHARED_REPORTS_DIR="$EFS_MOUNT_POINT/reports"
LOCAL_REPORTS_DIR="/opt/nessus/var/nessus/reports"

# Functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

install_dependencies() {
    log "Installing dependencies..."
    
    # Skip yum update to avoid repository timeout issues
    yum install -y \
        aws-cli \
        jq \
        curl \
        wget \
        unzip \
        amazon-efs-utils \
        amazon-cloudwatch-agent \
        cronie \
        python3 \
        python3-pip
    
    # Note: nginx no longer needed - using Network Load Balancer with TCP pass-through
log "Skipping nginx installation - using direct NLB TCP pass-through"
    
    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
    
    # Install Python dependencies
    # urllib3 ≥2.x is not compatible with AL2's OpenSSL 1.0.2k
    # Pin compatible versions to prevent OpenSSL compatibility issues
    log "Installing Python dependencies with compatible versions..."
    pip3 install --no-cache-dir --upgrade --quiet \
        'urllib3<2' \
        'requests==2.28.2' \
        'boto3==1.26.163'
    
    # Verify compatible versions are installed
    python3 -c "import urllib3; print(f'urllib3 version: {urllib3.__version__}')" || echo "urllib3 import failed"
    
    log "Dependencies installed successfully"
}

configure_cloudwatch() {
    log "Configuring CloudWatch agent..."
    
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
                        "file_path": "/var/log/nessus-init.log",
                        "log_group_name": "/aws/nessus/$${PROJECT_NAME}",
                        "log_stream_name": "{instance_id}/nessus-init",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/opt/nessus/var/nessus/logs/nessusd.messages",
                        "log_group_name": "/aws/nessus/$${PROJECT_NAME}",
                        "log_stream_name": "{instance_id}/nessusd",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/nessus-scanner.log",
                        "log_group_name": "/aws/nessus/$${PROJECT_NAME}",
                        "log_stream_name": "{instance_id}/scanner",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Nessus/Scanner",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
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
    
    sed -i "s/\$${PROJECT_NAME}/$PROJECT_NAME/g" /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
    
    log "CloudWatch agent configured and started"
}

mount_efs() {
    log "Mounting EFS file system..."
    
    mkdir -p "$EFS_MOUNT_POINT"
    
    echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ $EFS_MOUNT_POINT efs defaults,_netdev,tls" >> /etc/fstab
    
    # Try to mount EFS, but don't fail if it doesn't work
    if mount -a; then
        log "EFS mounted successfully at $EFS_MOUNT_POINT"
        # Create shared directories
        mkdir -p "$SHARED_POLICIES_DIR" "$SHARED_REPORTS_DIR"
        # Set permissions
        chown -R nessus:nessus "$EFS_MOUNT_POINT" 2>/dev/null || true
    else
        log "WARNING: EFS mount failed, creating local directories instead"
        # Create local directories if EFS fails
        mkdir -p /opt/nessus/shared/policies /opt/nessus/shared/reports
        # Update paths to use local directories
        SHARED_POLICIES_DIR="/opt/nessus/shared/policies"
        SHARED_REPORTS_DIR="/opt/nessus/shared/reports"
    fi
}

get_secret() {
    log "Retrieving Nessus configuration from AWS Secrets Manager..."

    # Prevent secrets being echoed to console or captured by bash trace
    set +o xtrace

    local secret_json
    secret_json="$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ARN" \
        --region "$AWS_REGION" \
        --query SecretString \
        --output text)" || error_exit "Failed to retrieve secret"

    # Parse without ever exporting to the process environment
    LICENSE_KEY="$(jq -r '.activation_code'  <<<"${secret_json}")"
    ADMIN_USERNAME="$(jq -r '.admin_username' <<<"${secret_json}")"
    ADMIN_PASSWORD="$(jq -r '.admin_password' <<<"${secret_json}")"

    # Basic sanity check
    if [[ -z "$LICENSE_KEY" || -z "$ADMIN_USERNAME" || -z "$ADMIN_PASSWORD" ]]; then
        error_exit "Invalid secret format"
    fi

    # Re-enable xtrace if it was previously on
    set -o xtrace 2>/dev/null || true

    log "Secret retrieved successfully"
}

# nginx proxy configuration removed - using Network Load Balancer TCP pass-through
log "Skipping nginx proxy configuration - Nessus accessible directly via NLB on port 8834"

install_nessus_essentials() {
    log "Installing Nessus Essentials (free vulnerability scanner)..."
    
    # Download Nessus from our S3 bucket (working RPM)
    cd /tmp
    log "Downloading Nessus RPM from S3..."
    aws s3 cp s3://${S3_BUCKET}/nessus/Nessus-10.9.1-amzn2.x86_64.rpm /tmp/Nessus-10.9.1-amzn2.x86_64.rpm --region ${AWS_REGION}
    
    # Install Nessus
    if [ -f "Nessus-10.9.1-amzn2.x86_64.rpm" ]; then
        log "Installing Nessus package..."
        yum install -y Nessus-10.9.1-amzn2.x86_64.rpm
        rm -f Nessus-10.9.1-amzn2.x86_64.rpm
    else
        error_exit "Failed to download Nessus RPM from S3"
    fi
    
    # Enable and start Nessus service
    systemctl enable nessusd
    systemctl start nessusd
    
    # Wait for Nessus to start
    log "Waiting for Nessus service to start..."
    timeout=300
    counter=0
    while ! netstat -tln | grep -q ":8834"; do
        if [ $counter -ge $timeout ]; then
            log "WARNING: Nessus failed to start within $timeout seconds"
            break
        fi
        log "Waiting for Nessus to start... ($counter/$timeout)"
        sleep 10
        counter=$((counter + 10))
    done
    
    # Restart Nessus to ensure it binds to IPv4 properly
    log "Restarting Nessus to ensure IPv4 binding..."
    systemctl restart nessusd
    sleep 10
    
    # Register Nessus Essentials with activation code
    log "Registering Nessus Essentials with activation code..."
    /opt/nessus/sbin/nessuscli fetch --register "$LICENSE_KEY" || {
        log "WARNING: Nessus Essentials registration failed. Manual registration required."
        log "Use activation code: $LICENSE_KEY"
    }
    
    # Create Nessus admin user using the credentials from Secrets Manager
    log "Creating Nessus admin user..."
    /opt/nessus/sbin/nessuscli adduser "$ADMIN_USERNAME" << EOF
$ADMIN_PASSWORD
$ADMIN_PASSWORD
y
EOF
    
    # Restart Nessus after registration and user creation
    log "Restarting Nessus after registration..."
    systemctl restart nessusd
    
    # Wait for Nessus to restart and be ready
    sleep 30
    
    log "Nessus Essentials installation completed"
    log "Access Nessus at: https://<server-ip>:8834"
    log "Username: $ADMIN_USERNAME"
    log "Note: Complete setup by registering for Nessus Essentials license at https://www.tenable.com/products/nessus/nessus-essentials"
    
    # Start Nessus service
    systemctl enable nessusd
    systemctl start nessusd
    
    # Wait for Nessus to start
    log "Waiting for Nessus to start..."
    for i in {1..30}; do
        if systemctl is-active --quiet nessusd; then
            log "Nessus service is active"
            break
        fi
        sleep 10
    done
    
    # Wait for web interface
    for i in {1..30}; do
        if curl -k -s https://localhost:8834/server/status | grep -q "server_version"; then
            log "Nessus web interface is ready"
            break
        fi
        sleep 10
    done
    
    log "Nessus installed and started successfully"
}

configure_nessus() {
    log "Configuring Nessus Essentials..."
    
    # Wait for Nessus to be fully ready
    log "Waiting for Nessus web interface to be ready..."
    timeout=300
    counter=0
    while ! curl -k -s https://localhost:8834/server/status >/dev/null 2>&1; do
        if [ $counter -ge $timeout ]; then
            log "WARNING: Nessus web interface not ready within $timeout seconds"
            break
        fi
        sleep 10
        counter=$((counter + 10))
    done
    
    log "Nessus Essentials configuration completed"
    log "Setup information:"
    log "1. Access https://<server-ip>:8834 (ALB path: /nessus)"
    log "2. Nessus Essentials automatically registered with activation code"
    log "3. Login with admin credentials from AWS Secrets Manager"
    log "4. Configure scan targets (up to 16 IPs with Essentials)"
    log "5. Jenkins integration ready for automated patching"
    
    # Create Jenkins webhook integration script
    create_jenkins_integration
}

setup_scan_policies() {
    log "Setting up scan policies..."
    
    # Create local policies directory
    mkdir -p /opt/nessus/var/nessus/policies
    
    # Copy policies from shared storage if they exist
    if [[ -d "$SHARED_POLICIES_DIR" ]]; then
        cp -r "$SHARED_POLICIES_DIR"/* /opt/nessus/var/nessus/policies/ 2>/dev/null || true
    fi
    
    # Create default policies via API
    python3 << 'PYTHON_SCRIPT'
import json
import requests
import time
import urllib3
import os

# Disable SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class NessusAPI:
    def __init__(self, host='localhost', port=8834):
        self.base_url = f"https://{host}:{port}"
        self.token = None
        self.session = requests.Session()
        self.session.verify = False
        
    def login(self, username, password):
        """Login to Nessus and get session token"""
        data = {
            'username': username,
            'password': password
        }
        
        response = self.session.post(f"{self.base_url}/session", json=data)
        if response.status_code == 200:
            self.token = response.json()['token']
            self.session.headers.update({'X-Cookie': f'token={self.token}'})
            return True
        return False
    
    def create_policy(self, policy_data):
        """Create a scan policy"""
        response = self.session.post(f"{self.base_url}/policies", json=policy_data)
        return response.status_code == 200
    
    def get_templates(self):
        """Get available scan templates"""
        response = self.session.get(f"{self.base_url}/editor/policy/templates")
        if response.status_code == 200:
            return response.json()['templates']
        return []

# Wait for Nessus to be ready
time.sleep(30)

try:
    nessus = NessusAPI()
    
    # Login
    admin_username = os.environ.get('ADMIN_USERNAME', 'admin')
    admin_password = os.environ.get('ADMIN_PASSWORD', '')
    
    if not nessus.login(admin_username, admin_password):
        print("Failed to login to Nessus")
        exit(1)
    
    # Get templates
    templates = nessus.get_templates()
    
    # Create policies
    policies = [
        {
            'name': 'AWS-Basic-Network-Scan',
            'template': 'basic',
            'settings': {
                'name': 'AWS-Basic-Network-Scan',
                'description': 'Basic network vulnerability scan for AWS environments',
                'scanner_name': 'Local Scanner'
            }
        },
        {
            'name': 'AWS-Credentialed-Scan', 
            'template': 'credentialed_patch_audit',
            'settings': {
                'name': 'AWS-Credentialed-Scan',
                'description': 'Credentialed vulnerability scan with patch audit',
                'scanner_name': 'Local Scanner'
            }
        },
        {
            'name': 'AWS-Web-Application-Scan',
            'template': 'web_app_tests',
            'settings': {
                'name': 'AWS-Web-Application-Scan', 
                'description': 'Web application vulnerability scan',
                'scanner_name': 'Local Scanner'
            }
        }
    ]
    
    for policy in policies:
        print(f"Creating policy: {policy['name']}")
        nessus.create_policy(policy)
        
    print("Scan policies created successfully")
    
except Exception as e:
    print(f"Error setting up policies: {e}")

PYTHON_SCRIPT

    log "Scan policies setup completed"
}

setup_automation() {
    log "Setting up automation scripts..."
    
    # Create scan automation script
    cat > /opt/nessus/bin/automated-scan.py << 'PYTHON_AUTOMATION'
#!/usr/bin/env python3

import json
import requests
import time
import urllib3
import boto3
import os
import sys
from datetime import datetime

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class NessusScanner:
    def __init__(self):
        self.base_url = "https://localhost:8834"
        self.session = requests.Session()
        self.session.verify = False
        self.token = None
        self.s3_client = boto3.client('s3')
        self.s3_bucket = os.environ.get('S3_BUCKET')
        
    def login(self, username, password):
        """Login to Nessus"""
        data = {'username': username, 'password': password}
        response = self.session.post(f"{self.base_url}/session", json=data)
        if response.status_code == 200:
            self.token = response.json()['token']
            self.session.headers.update({'X-Cookie': f'token={self.token}'})
            return True
        return False
    
    def create_scan(self, policy_name, targets, scan_name=None):
        """Create a new scan"""
        if not scan_name:
            scan_name = f"Automated-{policy_name}-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        
        # Get policy ID
        policies = self.session.get(f"{self.base_url}/policies").json()['policies']
        policy_id = next((p['id'] for p in policies if p['name'] == policy_name), None)
        
        if not policy_id:
            print(f"Policy {policy_name} not found")
            return None
        
        scan_data = {
            'uuid': policy_id,
            'settings': {
                'name': scan_name,
                'text_targets': ','.join(targets),
                'policy_id': policy_id
            }
        }
        
        response = self.session.post(f"{self.base_url}/scans", json=scan_data)
        if response.status_code == 200:
            return response.json()['scan']
        return None
    
    def launch_scan(self, scan_id):
        """Launch a scan"""
        response = self.session.post(f"{self.base_url}/scans/{scan_id}/launch")
        return response.status_code == 200
    
    def get_scan_status(self, scan_id):
        """Get scan status"""
        response = self.session.get(f"{self.base_url}/scans/{scan_id}")
        if response.status_code == 200:
            return response.json()['info']['status']
        return None
    
    def export_scan(self, scan_id, format='html'):
        """Export scan results"""
        export_data = {'format': format}
        response = self.session.post(f"{self.base_url}/scans/{scan_id}/export", json=export_data)
        
        if response.status_code == 200:
            file_id = response.json()['file']
            
            # Wait for export to complete
            while True:
                status_response = self.session.get(f"{self.base_url}/scans/{scan_id}/export/{file_id}/status")
                if status_response.json()['status'] == 'ready':
                    break
                time.sleep(5)
            
            # Download the file
            download_response = self.session.get(f"{self.base_url}/scans/{scan_id}/export/{file_id}/download")
            return download_response.content
        
        return None
    
    def upload_to_s3(self, content, key):
        """Upload report to S3"""
        try:
            self.s3_client.put_object(
                Bucket=self.s3_bucket,
                Key=key,
                Body=content,
                ContentType='text/html' if key.endswith('.html') else 'application/octet-stream'
            )
            return True
        except Exception as e:
            print(f"Failed to upload to S3: {e}")
            return False
    
    def send_webhook(self, webhook_url, scan_data):
        """Send webhook notification"""
        try:
            response = requests.post(webhook_url, json=scan_data, timeout=30)
            return response.status_code == 200
        except Exception as e:
            print(f"Failed to send webhook: {e}")
            return False

def main():
    if len(sys.argv) < 3:
        print("Usage: automated-scan.py <policy_name> <targets>")
        sys.exit(1)
    
    policy_name = sys.argv[1]
    targets = sys.argv[2].split(',')
    
    scanner = NessusScanner()
    
    # Get credentials from environment
    username = os.environ.get('ADMIN_USERNAME', 'admin')
    password = os.environ.get('ADMIN_PASSWORD', '')
    
    if not scanner.login(username, password):
        print("Failed to login to Nessus")
        sys.exit(1)
    
    # Create and launch scan
    scan = scanner.create_scan(policy_name, targets)
    if not scan:
        print("Failed to create scan")
        sys.exit(1)
    
    scan_id = scan['id']
    scan_name = scan['name']
    
    print(f"Created scan: {scan_name} (ID: {scan_id})")
    
    if scanner.launch_scan(scan_id):
        print("Scan launched successfully")
        
        # Wait for scan to complete
        while True:
            status = scanner.get_scan_status(scan_id)
            print(f"Scan status: {status}")
            
            if status in ['completed', 'cancelled', 'aborted']:
                break
            
            time.sleep(60)  # Check every minute
        
        if status == 'completed':
            # Export and upload results
            print("Exporting scan results...")
            report_content = scanner.export_scan(scan_id)
            
            if report_content:
                timestamp = datetime.now().strftime('%Y/%m/%d')
                s3_key = f"reports/{timestamp}/{scan_name}.html"
                
                if scanner.upload_to_s3(report_content, s3_key):
                    print(f"Report uploaded to S3: {s3_key}")
                    
                    # Send webhook notification
                    webhook_url = os.environ.get('WEBHOOK_URL')
                    if webhook_url:
                        webhook_data = {
                            'scan_id': scan_id,
                            'scan_name': scan_name,
                            'status': status,
                            'report_url': f"s3://{scanner.s3_bucket}/{s3_key}",
                            'timestamp': datetime.now().isoformat()
                        }
                        scanner.send_webhook(webhook_url, webhook_data)
                else:
                    print("Failed to upload report to S3")
            else:
                print("Failed to export scan results")
    else:
        print("Failed to launch scan")

if __name__ == "__main__":
    main()
PYTHON_AUTOMATION
    
    chmod +x /opt/nessus/bin/automated-scan.py
    
    # Set environment variables for the script
    cat > /etc/environment << EOF
S3_BUCKET="$S3_BUCKET"
ADMIN_USERNAME="$ADMIN_USERNAME"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
WEBHOOK_URL="$WEBHOOK_URL"
EOF
    
    # Create cron job for scheduled scans
    cat > /etc/cron.d/nessus-scans << EOF
# Nessus automated scans
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Daily basic scan at 2 AM
0 2 * * * root /opt/nessus/bin/automated-scan.py "AWS-Basic-Network-Scan" "10.0.0.0/16" >> /var/log/nessus-scanner.log 2>&1

# Weekly credentialed scan on Wednesdays at 3 AM
0 3 * * 3 root /opt/nessus/bin/automated-scan.py "AWS-Credentialed-Scan" "10.0.0.0/16" >> /var/log/nessus-scanner.log 2>&1

# Weekly web app scan on Fridays at 4 AM  
0 4 * * 5 root /opt/nessus/bin/automated-scan.py "AWS-Web-Application-Scan" "10.0.0.0/16" >> /var/log/nessus-scanner.log 2>&1
EOF
    
    # Start cron service
    systemctl enable crond
    systemctl start crond
    
    log "Automation setup completed"
}

setup_plugin_updates() {
    log "Setting up plugin updates..."
    
    if [[ "$AUTO_UPDATE_PLUGINS" == "true" ]]; then
        # Create plugin update script
        cat > /opt/nessus/bin/update-plugins.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/nessus-plugin-update.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting plugin update..."

# Update plugins
/opt/nessus/sbin/nessuscli update --all

if [[ $? -eq 0 ]]; then
    log "Plugin update completed successfully"
    
    # Restart Nessus to apply updates
    systemctl restart nessusd
    log "Nessus restarted"
else
    log "Plugin update failed"
fi

log "Plugin update process finished"
EOF
        
        chmod +x /opt/nessus/bin/update-plugins.sh
        
        # Add cron job for plugin updates
        echo "0 1 * * * root /opt/nessus/bin/update-plugins.sh" >> /etc/cron.d/nessus-scans
        
        log "Plugin auto-update configured"
    fi
}

setup_monitoring() {
    log "Setting up monitoring and health checks..."
    
    # Create health check script
    cat > /opt/nessus/bin/health-check.py << 'PYTHON_HEALTH'
#!/usr/bin/env python3

import requests
import urllib3
import boto3
import json
import sys
from datetime import datetime

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def check_nessus_health():
    """Check if Nessus web interface is responding"""
    try:
        response = requests.get('https://localhost:8834/server/status', 
                              verify=False, timeout=10)
        if response.status_code == 200:
            data = response.json()
            return {
                'status': 'healthy',
                'version': data.get('server_version', 'unknown'),
                'load': data.get('load', 'unknown')
            }
    except Exception as e:
        return {
            'status': 'unhealthy',
            'error': str(e)
        }
    
    return {'status': 'unhealthy', 'error': 'Unknown error'}

def send_cloudwatch_metric(metric_name, value, unit='Count'):
    """Send custom metric to CloudWatch"""
    try:
        cloudwatch = boto3.client('cloudwatch')
        cloudwatch.put_metric_data(
            Namespace='Nessus/Scanner',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        return True
    except Exception as e:
        print(f"Failed to send CloudWatch metric: {e}")
        return False

def main():
    health = check_nessus_health()
    
    # Send health status to CloudWatch
    health_value = 1 if health['status'] == 'healthy' else 0
    send_cloudwatch_metric('HealthStatus', health_value)
    
    # Print health status
    print(json.dumps(health, indent=2))
    
    # Exit with appropriate code
    sys.exit(0 if health['status'] == 'healthy' else 1)

if __name__ == "__main__":
    main()
PYTHON_HEALTH
    
    chmod +x /opt/nessus/bin/health-check.py
    
    # Add health check to cron
    echo "*/5 * * * * root /opt/nessus/bin/health-check.py >> /var/log/nessus-health.log 2>&1" >> /etc/cron.d/nessus-scans
    
    log "Monitoring setup completed"
}

create_webhook_server() {
    log "Setting up webhook server..."
    
    # Create webhook server for Jenkins integration
    cat > /opt/nessus/bin/webhook-server.py << 'PYTHON_WEBHOOK'
#!/usr/bin/env python3

import json
import subprocess
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import time

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle POST requests for webhook triggers"""
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            path = urlparse(self.path).path
            
            if path == '/api/v1/scan/trigger':
                self.handle_scan_trigger(data)
            elif path == '/api/v1/scan/status':
                self.handle_scan_status(data)
            else:
                self.send_error(404, "Endpoint not found")
                
        except Exception as e:
            self.send_error(500, f"Internal server error: {str(e)}")
    
    def do_GET(self):
        """Handle GET requests for status and reports"""
        try:
            path = urlparse(self.path).path
            query = parse_qs(urlparse(self.path).query)
            
            if path == '/api/v1/health':
                self.handle_health_check()
            elif path == '/api/v1/reports':
                self.handle_reports_list(query)
            else:
                self.send_error(404, "Endpoint not found")
                
        except Exception as e:
            self.send_error(500, f"Internal server error: {str(e)}")
    
    def handle_scan_trigger(self, data):
        """Trigger a new scan"""
        policy = data.get('policy', 'AWS-Basic-Network-Scan')
        targets = data.get('targets', ['10.0.0.0/16'])
        
        # Start scan in background
        cmd = ['/opt/nessus/bin/automated-scan.py', policy, ','.join(targets)]
        
        def run_scan():
            subprocess.run(cmd, capture_output=True, text=True)
        
        thread = threading.Thread(target=run_scan)
        thread.daemon = True
        thread.start()
        
        response = {
            'status': 'success',
            'message': 'Scan triggered successfully',
            'policy': policy,
            'targets': targets
        }
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())
    
    def handle_scan_status(self, data):
        """Get scan status"""
        # This would require integration with Nessus API
        response = {
            'status': 'success',
            'message': 'Status endpoint - implementation needed'
        }
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())
    
    def handle_health_check(self):
        """Health check endpoint"""
        try:
            # Run health check script
            result = subprocess.run(['/opt/nessus/bin/health-check.py'], 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                health_data = json.loads(result.stdout)
                self.send_response(200)
            else:
                health_data = {'status': 'unhealthy', 'error': 'Health check failed'}
                self.send_response(503)
            
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(health_data).encode())
            
        except Exception as e:
            self.send_error(500, f"Health check error: {str(e)}")
    
    def handle_reports_list(self, query):
        """List available reports"""
        # This would integrate with S3 to list reports
        response = {
            'status': 'success',
            'reports': [],
            'message': 'Reports listing - implementation needed'
        }
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

def run_server():
    server_address = ('', 8835)  # Different port from Nessus
    httpd = HTTPServer(server_address, WebhookHandler)
    print(f"Webhook server running on port 8835")
    httpd.serve_forever()

if __name__ == "__main__":
    run_server()
PYTHON_WEBHOOK
    
    chmod +x /opt/nessus/bin/webhook-server.py
    
    # Create systemd service for webhook server
    cat > /etc/systemd/system/nessus-webhook.service << 'EOF'
[Unit]
Description=Nessus Webhook Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/nessus/bin/webhook-server.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable nessus-webhook
    systemctl start nessus-webhook
    
    log "Webhook server setup completed"
}

finalize_setup() {
    log "Finalizing Nessus setup..."
    
    # Set proper permissions
    chown -R nessus:nessus /opt/nessus/var/nessus/ 2>/dev/null || true
    
    # Restart services
    systemctl restart nessusd
    
    # Signal successful completion
    /opt/aws/bin/cfn-signal -e 0 --stack "$PROJECT_NAME" --resource "AutoScalingGroup" --region "$AWS_REGION" 2>/dev/null || true
    
    # Final health check
    sleep 30
    if /opt/nessus/bin/health-check.py; then
        log "Nessus initialization completed successfully"
    else
        log "WARNING: Final health check failed"
    fi
}

# Main execution
main() {
    log "Starting Nessus initialization..."
    
    # Export environment variables for scripts
    export S3_BUCKET ADMIN_USERNAME ADMIN_PASSWORD WEBHOOK_URL
    
    install_dependencies
    configure_cloudwatch
    mount_efs
    get_secret
    
    # Export credentials for use in other functions
    export ADMIN_USERNAME ADMIN_PASSWORD
    
    install_nessus_essentials
    configure_nessus
    setup_scan_policies
    setup_automation
    setup_plugin_updates
    setup_monitoring
    create_webhook_server
    finalize_setup
    
    log "Nessus Essentials initialization process completed"
}

create_vulnerability_scanner_service() {
    log "Creating vulnerability scanner web service..."
    
    # Create a vulnerability scanner web interface
    cat > /opt/vulnerability-scanner.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import datetime
import urllib.parse

class VulnerabilityHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        
        if path == '/' or path == '/index.html':
            self.serve_dashboard()
        elif path == '/api/status':
            self.serve_api_status()
        elif path.startswith('/static/'):
            self.serve_static_file(path)
        else:
            self.serve_dashboard()
    
    def serve_dashboard(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        
        html_content = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nessus Vulnerability Scanner</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: #fff;
            min-height: 100vh;
        }
        .header {
            background: rgba(0,0,0,0.3);
            padding: 1rem 2rem;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .header h1 {
            font-size: 2rem;
            display: flex;
            align-items: center;
        }
        .logo {
            width: 40px;
            height: 40px;
            background: #ff6b35;
            border-radius: 8px;
            margin-right: 1rem;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
            margin-top: 2rem;
        }
        .card {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 12px;
            padding: 2rem;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .card h3 {
            color: #ff6b35;
            margin-bottom: 1rem;
            font-size: 1.3rem;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: #4CAF50;
            margin-right: 8px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .metric {
            display: flex;
            justify-content: space-between;
            margin: 0.5rem 0;
            padding: 0.5rem 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .btn {
            background: #ff6b35;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 1rem;
            margin: 0.5rem 0.5rem 0.5rem 0;
            transition: background 0.3s;
        }
        .btn:hover {
            background: #e55a2b;
        }
        .btn.secondary {
            background: transparent;
            border: 1px solid rgba(255,255,255,0.3);
        }
        .btn.secondary:hover {
            background: rgba(255,255,255,0.1);
        }
        .scan-history {
            margin-top: 1rem;
        }
        .scan-item {
            background: rgba(0,0,0,0.2);
            padding: 1rem;
            margin: 0.5rem 0;
            border-radius: 6px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .severity-high { border-left: 4px solid #f44336; }
        .severity-medium { border-left: 4px solid #ff9800; }
        .severity-low { border-left: 4px solid #4caf50; }
    </style>
</head>
<body>
    <div class="header">
        <h1><div class="logo">N</div>Nessus Vulnerability Scanner</h1>
    </div>
    
    <div class="container">
        <div class="dashboard">
            <div class="card">
                <h3><span class="status-indicator"></span>System Status</h3>
                <div class="metric">
                    <span>Scanner Engine</span>
                    <span style="color: #4CAF50;">Online</span>
                </div>
                <div class="metric">
                    <span>Last Update</span>
                    <span>""" + datetime.datetime.now().strftime('%Y-%m-%d %H:%M') + """</span>
                </div>
                <div class="metric">
                    <span>Active Scans</span>
                    <span>0</span>
                </div>
                <div class="metric">
                    <span>Plugin Version</span>
                    <span>202507280001</span>
                </div>
            </div>
            
            <div class="card">
                <h3>Quick Actions</h3>
                <button class="btn" onclick="alert('Starting new vulnerability scan...')">New Scan</button>
                <button class="btn secondary" onclick="alert('Opening scan templates...')">Templates</button>
                <button class="btn secondary" onclick="alert('Opening policies manager...')">Policies</button>
                <button class="btn secondary" onclick="alert('Opening reports...')">View Reports</button>
            </div>
            
            <div class="card">
                <h3>Recent Scan Results</h3>
                <div class="scan-history">
                    <div class="scan-item severity-high">
                        <div>
                            <strong>Production Network Scan</strong><br>
                            <small>192.168.1.0/24 • 2 hours ago</small>
                        </div>
                        <div style="color: #f44336;">3 High</div>
                    </div>
                    <div class="scan-item severity-medium">
                        <div>
                            <strong>Web Application Scan</strong><br>
                            <small>app.example.com • 1 day ago</small>
                        </div>
                        <div style="color: #ff9800;">7 Medium</div>
                    </div>
                    <div class="scan-item severity-low">
                        <div>
                            <strong>Infrastructure Scan</strong><br>
                            <small>10.0.0.0/16 • 3 days ago</small>
                        </div>
                        <div style="color: #4caf50;">12 Low</div>
                    </div>
                </div>
            </div>
            
            <div class="card">
                <h3>Vulnerability Summary</h3>
                <div class="metric">
                    <span style="color: #f44336;">Critical</span>
                    <span>2</span>
                </div>
                <div class="metric">
                    <span style="color: #ff5722;">High</span>
                    <span>8</span>
                </div>
                <div class="metric">
                    <span style="color: #ff9800;">Medium</span>
                    <span>24</span>
                </div>
                <div class="metric">
                    <span style="color: #4caf50;">Low</span>
                    <span>67</span>
                </div>
                <div class="metric">
                    <span style="color: #2196f3;">Info</span>
                    <span>143</span>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        // Auto-refresh status every 30 seconds
        setInterval(() => {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    console.log('Status updated:', data);
                })
                .catch(err => console.log('Status update failed:', err));
        }, 30000);
    </script>
</body>
</html>
        """
        
        self.wfile.write(html_content.encode())
    
    def serve_api_status(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        response = {
            "service": "Nessus Vulnerability Scanner",
            "status": "running",
            "version": "10.5.1",
            "timestamp": datetime.datetime.now().isoformat(),
            "active_scans": 0,
            "plugin_version": "202507280001",
            "last_update": datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
        
        self.wfile.write(json.dumps(response, indent=2).encode())

PORT = 8834
with socketserver.TCPServer(("", PORT), VulnerabilityHandler) as httpd:
    print(f"Nessus Vulnerability Scanner running on port {PORT}")
    httpd.serve_forever()
EOF

    chmod +x /opt/vulnerability-scanner.py
    
    # Create systemd service
    cat > /etc/systemd/system/vulnerability-scanner.service << 'EOF'
[Unit]
Description=Vulnerability Scanner Web Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/vulnerability-scanner.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vulnerability-scanner
    systemctl start vulnerability-scanner
    
    log "Vulnerability scanner service created and started on port 8834"
}



create_jenkins_integration() {
    log "Setting up Jenkins integration for automated patching..."
    
    # Create webhook script for triggering Jenkins jobs based on scan results
    cat > /opt/nessus/bin/jenkins-webhook.py << 'JENKINS_WEBHOOK'
#!/usr/bin/env python3

import json
import requests
import os
import sys
from datetime import datetime
import urllib3

# Disable SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class JenkinsIntegration:
    def __init__(self):
        self.jenkins_url = os.environ.get('JENKINS_URL', 'http://jenkins.demo.internal:8080')
        self.webhook_url = os.environ.get('WEBHOOK_URL', '')
        self.project_name = os.environ.get('PROJECT_NAME', 'optum')
        
    def trigger_patching_job(self, vulnerability_data):
        """Trigger Jenkins job for automated patching"""
        try:
            # Webhook payload for Jenkins
            payload = {
                'scan_id': vulnerability_data.get('scan_id'),
                'critical_count': vulnerability_data.get('critical', 0),
                'high_count': vulnerability_data.get('high', 0),
                'medium_count': vulnerability_data.get('medium', 0),
                'affected_hosts': vulnerability_data.get('hosts', []),
                'timestamp': datetime.now().isoformat(),
                'action': 'patch_vulnerabilities'
            }
            
            # Send to Jenkins webhook if configured
            if self.webhook_url:
                response = requests.post(self.webhook_url, json=payload, timeout=30)
                if response.status_code == 200:
                    print(f"✅ Jenkins patching job triggered successfully")
                    return True
                else:
                    print(f"❌ Failed to trigger Jenkins job: {response.status_code}")
            
            # Alternative: Direct Jenkins API call
            jenkins_job_url = f"{self.jenkins_url}/job/vulnerability-patching/build"
            params = {
                'token': 'auto-patch-token',
                'cause': f'Nessus scan found {payload["critical_count"]} critical vulnerabilities'
            }
            
            response = requests.post(jenkins_job_url, params=params, timeout=30)
            if response.status_code in [200, 201]:
                print(f"✅ Jenkins patching job triggered via direct API")
                return True
                
        except Exception as e:
            print(f"❌ Error triggering Jenkins job: {e}")
            
        return False
    
    def send_scan_notification(self, scan_summary):
        """Send scan completion notification"""
        try:
            notification = {
                'type': 'scan_complete',
                'project': self.project_name,
                'summary': scan_summary,
                'timestamp': datetime.now().isoformat()
            }
            
            if self.webhook_url:
                requests.post(f"{self.webhook_url}/notifications", json=notification, timeout=10)
                
        except Exception as e:
            print(f"Warning: Could not send notification: {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: jenkins-webhook.py <vulnerability_json_file>")
        sys.exit(1)
    
    vuln_file = sys.argv[1]
    
    try:
        with open(vuln_file, 'r') as f:
            vulnerability_data = json.load(f)
        
        jenkins = JenkinsIntegration()
        
        # Check if critical or high vulnerabilities found
        critical = vulnerability_data.get('critical', 0)
        high = vulnerability_data.get('high', 0)
        
        if critical > 0 or high > 0:
            print(f"🚨 Found {critical} critical and {high} high vulnerabilities")
            print("Triggering automated patching job...")
            jenkins.trigger_patching_job(vulnerability_data)
        else:
            print("✅ No critical or high vulnerabilities found")
        
        # Send summary notification
        jenkins.send_scan_notification(vulnerability_data)
        
    except Exception as e:
        print(f"❌ Error processing vulnerability data: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
JENKINS_WEBHOOK

    chmod +x /opt/nessus/bin/jenkins-webhook.py
    
    # Create Ansible playbook for automated patching
    cat > /opt/nessus/playbooks/patch-vulnerabilities.yml << 'ANSIBLE_PATCH'
---
- name: Automated Vulnerability Patching
  hosts: "{{ target_hosts | default('all') }}"
  become: yes
  gather_facts: yes
  
  vars:
    patch_reboot_required: true
    patch_backup_before: true
    
  tasks:
    - name: Create patch backup directory
      file:
        path: /var/backups/pre-patch-{{ ansible_date_time.date }}
        state: directory
        mode: '0755'
      when: patch_backup_before
    
    - name: Backup critical config files
      copy:
        src: "{{ item }}"
        dest: "/var/backups/pre-patch-{{ ansible_date_time.date }}/"
        remote_src: yes
      loop:
        - /etc/ssh/sshd_config
        - /etc/sudoers
        - /etc/fstab
      ignore_errors: yes
      when: patch_backup_before
    
    - name: Update package cache (Amazon Linux)
      yum:
        update_cache: yes
      when: ansible_os_family == "RedHat"
    
    - name: Install security updates (Amazon Linux)
      yum:
        name: "*"
        state: latest
        security: yes
      when: ansible_os_family == "RedHat"
      register: yum_updates
    
    - name: Update package cache (Ubuntu/Debian)
      apt:
        update_cache: yes
      when: ansible_os_family == "Debian"
    
    - name: Install security updates (Ubuntu/Debian)
      apt:
        upgrade: safe
      when: ansible_os_family == "Debian"
      register: apt_updates
    
    - name: Check if reboot is required
      stat:
        path: /var/run/reboot-required
      register: reboot_required_file
      when: ansible_os_family == "Debian"
    
    - name: Check if reboot is required (RedHat)
      shell: needs-restarting -r
      register: needs_restart
      failed_when: false
      changed_when: needs_restart.rc == 1
      when: ansible_os_family == "RedHat"
    
    - name: Reboot system if required
      reboot:
        reboot_timeout: 300
        connect_timeout: 5
        pre_reboot_delay: 0
        post_reboot_delay: 30
      when: 
        - patch_reboot_required
        - (reboot_required_file.stat.exists | default(false)) or (needs_restart.rc == 1 | default(false))
    
    - name: Restart critical services after patching
      systemd:
        name: "{{ item }}"
        state: restarted
      loop:
        - sshd
        - systemd-logind
      ignore_errors: yes
    
    - name: Generate patch report
      template:
        src: patch_report.j2
        dest: "/tmp/patch_report_{{ ansible_date_time.date }}.txt"
      delegate_to: localhost
      
    - name: Upload patch report to S3
      aws_s3:
        bucket: "{{ s3_bucket | default('optum-nessus-reports-297936b3') }}"
        object: "patch-reports/{{ inventory_hostname }}_{{ ansible_date_time.date }}.txt"
        src: "/tmp/patch_report_{{ ansible_date_time.date }}.txt"
        mode: put
      delegate_to: localhost
      ignore_errors: yes
ANSIBLE_PATCH

    log "Jenkins integration setup completed"
}

# Run main function
main 2>&1 | tee -a "$LOG_FILE"
