#!/bin/bash

# Update system
yum update -y

# Install packages including some with known vulnerabilities for demo
yum install -y \
    httpd \
    php \
    mysql \
    wget \
    curl \
    git \
    unzip \
    telnet-server \
    vsftpd \
    xinetd \
    awscli

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm
rm amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
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
                        "file_path": "/var/log/httpd/access_log",
                        "log_group_name": "/aws/ec2/app-servers/${aws_region}",
                        "log_stream_name": "{instance_id}/httpd-access"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "/aws/ec2/app-servers/${aws_region}",
                        "log_stream_name": "{instance_id}/httpd-error"
                    },
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/app-servers/${aws_region}",
                        "log_stream_name": "{instance_id}/messages"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "OptumDemo/AppServers",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
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
                "resources": ["*"]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
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

# Configure Apache with intentional vulnerabilities
systemctl start httpd
systemctl enable httpd

# Create a vulnerable web application
cat > /var/www/html/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Optum UK Demo - Vulnerable Web App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .warning { background: #ffebee; padding: 20px; border-left: 5px solid #f44336; margin-bottom: 20px; }
        .info { background: #e3f2fd; padding: 20px; border-left: 5px solid #2196f3; margin-bottom: 20px; }
        .vulnerability { background: #fff3e0; padding: 15px; margin: 10px 0; border: 1px solid #ff9800; }
    </style>
</head>
<body>
    <h1>Optum UK Demo - Vulnerable Application</h1>
    
    <div class="warning">
        <strong>Warning:</strong> This application contains intentional security vulnerabilities for demonstration purposes only.
        Do not deploy this in production environments.
    </div>
    
    <div class="info">
        <strong>Purpose:</strong> This application is designed to be scanned by Nessus to demonstrate vulnerability detection capabilities.
    </div>
    
    <h2>Application Information</h2>
    <p><strong>Server:</strong> <?php echo gethostname(); ?></p>
    <p><strong>PHP Version:</strong> <?php echo phpversion(); ?></p>
    <p><strong>Server Software:</strong> <?php echo $_SERVER['SERVER_SOFTWARE']; ?></p>
    <p><strong>Time:</strong> <?php echo date('Y-m-d H:i:s'); ?></p>
    
    <h2>Intentional Vulnerabilities</h2>
    <div class="vulnerability">
        <h3>1. SQL Injection (Simulated)</h3>
        <form method="GET">
            <input type="text" name="search" placeholder="Search..." value="<?php echo isset($_GET['search']) ? $_GET['search'] : ''; ?>">
            <button type="submit">Search</button>
        </form>
        <?php
        if (isset($_GET['search'])) {
            // Intentionally vulnerable - echoing user input without sanitization
            echo "<p>Searching for: " . $_GET['search'] . "</p>";
        }
        ?>
    </div>
    
    <div class="vulnerability">
        <h3>2. Directory Listing</h3>
        <p><a href="/uploads/">View uploads directory</a> (if exists)</p>
    </div>
    
    <div class="vulnerability">
        <h3>3. Information Disclosure</h3>
        <p><a href="/phpinfo.php">View PHP Info</a></p>
        <p><a href="/server-status">View Server Status</a> (if enabled)</p>
    </div>
    
    <div class="vulnerability">
        <h3>4. Weak Authentication</h3>
        <form method="POST">
            <input type="text" name="username" placeholder="Username">
            <input type="password" name="password" placeholder="Password">
            <button type="submit">Login</button>
        </form>
        <?php
        if (isset($_POST['username']) && isset($_POST['password'])) {
            // Weak authentication check
            if ($_POST['username'] == 'admin' && $_POST['password'] == 'password') {
                echo "<p style='color: green;'>Login successful!</p>";
            } else {
                echo "<p style='color: red;'>Login failed!</p>";
            }
        }
        ?>
    </div>
    
    <h2>Health Check</h2>
    <p><a href="/health">Health Check Endpoint</a></p>
    
</body>
</html>
EOF

# Create phpinfo page (information disclosure vulnerability)
cat > /var/www/html/phpinfo.php << 'EOF'
<?php
phpinfo();
?>
EOF

# Create health check endpoint
cat > /var/www/html/health << 'EOF'
OK
EOF

# Create uploads directory with directory listing enabled
mkdir -p /var/www/html/uploads
echo "Upload functionality disabled for security" > /var/www/html/uploads/readme.txt

# Configure Apache with vulnerable settings
cat >> /etc/httpd/conf/httpd.conf << 'EOF'

# Intentional vulnerabilities for demo
ServerTokens Full
ServerSignature On

# Enable server-status (information disclosure)
<Location "/server-status">
    SetHandler server-status
    Require all granted
</Location>

# Directory listing for uploads
<Directory "/var/www/html/uploads">
    Options +Indexes
    AllowOverride None
    Require all granted
</Directory>
EOF

# Configure Telnet (intentional vulnerability)
systemctl enable telnet.socket
systemctl start telnet.socket

# Configure FTP (intentional vulnerability)
cat > /etc/vsftpd/vsftpd.conf << 'EOF'
anonymous_enable=YES
local_enable=YES
write_enable=YES
local_umask=022
anon_upload_enable=YES
anon_mkdir_write_enable=YES
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
listen=YES
pam_service_name=vsftpd
userlist_enable=YES
tcp_wrappers=YES
EOF

systemctl enable vsftpd
systemctl start vsftpd

# Create some fake sensitive files for testing
mkdir -p /var/backups
echo "database_password=supersecret123" > /var/backups/config.txt
echo "api_key=ak_test_12345" > /var/backups/api_keys.txt
chmod 644 /var/backups/*.txt

# Install and configure SSH with weaker settings for demo
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# Create weak user accounts for demo
useradd -m testuser
echo "testuser:password123" | chpasswd
useradd -m admin
echo "admin:admin" | chpasswd

# Set hostname
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
if [ -n "$TOKEN" ]; then
    INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
else
    INSTANCE_ID="unknown"
fi
hostnamectl set-hostname "app-server-$INSTANCE_ID"

# Create startup script to ensure services are running
cat > /etc/rc.d/rc.local << 'EOF'
#!/bin/bash
systemctl start httpd
systemctl start vsftpd
systemctl start telnet.socket
EOF
chmod +x /etc/rc.d/rc.local

# Restart services
systemctl restart httpd
systemctl restart vsftpd

echo "App server setup completed at $(date)" >> /var/log/user-data.log
echo "Intentional vulnerabilities configured for Nessus testing" >> /var/log/user-data.log
