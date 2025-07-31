#!/bin/bash

# Jenkins Pipeline Configuration Script
# This script creates pipeline job configurations and DSL scripts

set -euo pipefail

JENKINS_HOME="${jenkins_home}"
JENKINS_USER="${jenkins_user}"
PROJECT="${project}"
ENVIRONMENT="${environment}"

echo "=== Setting up Jenkins Pipeline Configurations ==="

# Create Job DSL scripts directory
mkdir -p "$JENKINS_HOME/dsl-scripts"

# Infrastructure Provisioning Pipeline DSL
cat > "$JENKINS_HOME/dsl-scripts/infrastructure-pipeline.groovy" << 'INFRA_DSL'
// Infrastructure Provisioning Pipeline Job DSL

pipelineJob('infrastructure-provisioning') {
    displayName('Infrastructure Provisioning Pipeline')
    description('Automated infrastructure provisioning using Terraform')
    
    parameters {
        choiceParam('ENVIRONMENT', ['dev', 'staging', 'prod'], 'Target environment')
        choiceParam('REGION', ['eu-west-1', 'us-east-1', 'us-west-2', 'ap-southeast-1'], 'AWS Region')
        choiceParam('INSTANCE_SIZE', ['demo', 'full'], 'Deployment mode')
        booleanParam('DESTROY', false, 'Destroy infrastructure instead of creating')
        stringParam('TERRAFORM_VERSION', '1.6.0', 'Terraform version to use')
    }
    
    properties {
        githubProjectProperty {
            projectUrl('https://github.com/Dwalker0357/Optum_UK_AWS_Demo')
        }
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('10')
                    daysToKeepStr('30')
                }
            }
        }
    }
    
    triggers {
        githubPush()
        cron('H 2 * * 1-5') // Weekdays at 2 AM
    }
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/Dwalker0357/Optum_UK_AWS_Demo.git')
                        credentials('github-token')
                    }
                    branch('main')
                }
            }
            scriptPath('jenkins/pipelines/infrastructure.jenkinsfile')
            lightweight(true)
        }
    }
}

// Multi-region Infrastructure Pipeline
pipelineJob('multi-region-infrastructure') {
    displayName('Multi-Region Infrastructure Pipeline')
    description('Deploy infrastructure across multiple regions')
    
    parameters {
        booleanParam('DEPLOY_ALL_REGIONS', false, 'Deploy to all configured regions')
        checkboxParameter {
            name('REGIONS')
            choices(['eu-west-1', 'us-east-1', 'us-west-2', 'ap-southeast-1', 'ca-central-1'])
            description('Select regions to deploy')
        }
        choiceParam('INSTANCE_SIZE', ['demo', 'full'], 'Deployment mode')
    }
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/Dwalker0357/Optum_UK_AWS_Demo.git')
                        credentials('github-token')
                    }
                    branch('main')
                }
            }
            scriptPath('jenkins/pipelines/multi-region.jenkinsfile')
            lightweight(true)
        }
    }
}
INFRA_DSL

# Security Scanning Pipeline DSL
cat > "$JENKINS_HOME/dsl-scripts/security-pipeline.groovy" << 'SECURITY_DSL'
// Security Scanning Pipeline Job DSL

pipelineJob('security-scanning') {
    displayName('Security Scanning Pipeline')
    description('Automated security scanning with Nessus integration')
    
    parameters {
        choiceParam('SCAN_TYPE', ['basic', 'compliance', 'full'], 'Type of security scan')
        choiceParam('TARGET_ENVIRONMENT', ['dev', 'staging', 'prod'], 'Environment to scan')
        stringParam('TARGET_HOSTS', '', 'Comma-separated list of hosts to scan (optional)')
        booleanParam('NESSUS_SCAN', true, 'Enable Nessus vulnerability scanning')
        booleanParam('COMPLIANCE_CHECK', true, 'Enable compliance checking')
    }
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('20')
                    daysToKeepStr('60')
                }
            }
        }
    }
    
    triggers {
        cron('H 2 * * *') // Daily at 2 AM
        upstream('infrastructure-provisioning', 'SUCCESS')
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'linux && docker && security'
                    }
                    
                    environment {
                        NESSUS_URL = credentials('nessus-url')
                        NESSUS_ACCESS_KEY = credentials('nessus-access-key')
                        NESSUS_SECRET_KEY = credentials('nessus-secret-key')
                    }
                    
                    stages {
                        stage('Discover Targets') {
                            steps {
                                script {
                                    if (params.TARGET_HOSTS) {
                                        env.SCAN_TARGETS = params.TARGET_HOSTS
                                    } else {
                                        env.SCAN_TARGETS = sh(
                                            script: """
                                                aws ec2 describe-instances \\
                                                    --filters "Name=tag:Environment,Values=${params.TARGET_ENVIRONMENT}" \\
                                                              "Name=instance-state-name,Values=running" \\
                                                    --query 'Reservations[].Instances[].PrivateIpAddress' \\
                                                    --output text | tr '\\t' ','
                                            """,
                                            returnStdout: true
                                        ).trim()
                                    }
                                }
                                echo "Scan targets: ${env.SCAN_TARGETS}"
                            }
                        }
                        
                        stage('Nessus Scan') {
                            when {
                                expression { params.NESSUS_SCAN }
                            }
                            steps {
                                script {
                                    def scanId = sh(
                                        script: """
                                            python3 /opt/nessus-scripts/launch-scan.py \\
                                                --targets "${env.SCAN_TARGETS}" \\
                                                --scan-type "${params.SCAN_TYPE}" \\
                                                --environment "${params.TARGET_ENVIRONMENT}"
                                        """,
                                        returnStdout: true
                                    ).trim()
                                    
                                    env.NESSUS_SCAN_ID = scanId
                                    echo "Nessus scan launched: ${scanId}"
                                }
                            }
                        }
                        
                        stage('Wait for Scan Completion') {
                            when {
                                expression { params.NESSUS_SCAN && env.NESSUS_SCAN_ID }
                            }
                            steps {
                                script {
                                    timeout(time: 2, unit: 'HOURS') {
                                        waitUntil {
                                            script {
                                                def status = sh(
                                                    script: """
                                                        python3 /opt/nessus-scripts/check-scan-status.py \\
                                                            --scan-id "${env.NESSUS_SCAN_ID}"
                                                    """,
                                                    returnStdout: true
                                                ).trim()
                                                return status == 'completed'
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        stage('Generate Reports') {
                            steps {
                                script {
                                    if (params.NESSUS_SCAN && env.NESSUS_SCAN_ID) {
                                        sh """
                                            python3 /opt/nessus-scripts/export-report.py \\
                                                --scan-id "${env.NESSUS_SCAN_ID}" \\
                                                --format pdf \\
                                                --output-dir "${WORKSPACE}/reports"
                                        """
                                    }
                                    
                                    if (params.COMPLIANCE_CHECK) {
                                        sh """
                                            ansible-playbook /opt/ansible-playbooks/compliance-check.yml \\
                                                -i "${env.SCAN_TARGETS}" \\
                                                --extra-vars "environment=${params.TARGET_ENVIRONMENT}"
                                        """
                                    }
                                }
                            }
                        }
                        
                        stage('Archive Results') {
                            steps {
                                archiveArtifacts artifacts: 'reports/**/*', allowEmptyArchive: true
                                publishHTML([
                                    allowMissing: false,
                                    alwaysLinkToLastBuild: true,
                                    keepAll: true,
                                    reportDir: 'reports',
                                    reportFiles: '*.html',
                                    reportName: 'Security Scan Report'
                                ])
                            }
                        }
                    }
                    
                    post {
                        always {
                            cleanWs()
                        }
                        success {
                            echo 'Security scan completed successfully'
                        }
                        failure {
                            echo 'Security scan failed'
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}

// Nessus Webhook Handler
pipelineJob('nessus-webhook-handler') {
    displayName('Nessus Webhook Handler')
    description('Handles Nessus scan completion webhooks')
    
    properties {
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('50')
                    daysToKeepStr('30')
                }
            }
        }
        pipelineTriggers {
            triggers {
                genericTrigger {
                    genericVariables {
                        genericVariable {
                            key('SCAN_ID')
                            value('$.scan_id')
                            expressionType('JSONPath')
                        }
                        genericVariable {
                            key('SCAN_STATUS')
                            value('$.status')
                            expressionType('JSONPath')
                        }
                        genericVariable {
                            key('SCAN_NAME')
                            value('$.scan_name')
                            expressionType('JSONPath')
                        }
                    }
                    token('nessus-webhook-token')
                    causeString('Nessus scan webhook triggered')
                    printContributedVariables(true)
                    printPostContent(true)
                }
            }
        }
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent any
                    
                    stages {
                        stage('Process Webhook') {
                            steps {
                                script {
                                    echo "Received Nessus webhook:"
                                    echo "Scan ID: ${env.SCAN_ID}"
                                    echo "Status: ${env.SCAN_STATUS}"
                                    echo "Scan Name: ${env.SCAN_NAME}"
                                    
                                    if (env.SCAN_STATUS == 'completed') {
                                        // Trigger downstream jobs for report processing
                                        build job: 'process-scan-results', parameters: [
                                            string(name: 'SCAN_ID', value: env.SCAN_ID),
                                            string(name: 'SCAN_NAME', value: env.SCAN_NAME)
                                        ]
                                    }
                                }
                            }
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}
SECURITY_DSL

# Application Deployment Pipeline DSL
cat > "$JENKINS_HOME/dsl-scripts/application-pipeline.groovy" << 'APP_DSL'
// Application Deployment Pipeline Job DSL

pipelineJob('application-deployment') {
    displayName('Application Deployment Pipeline')
    description('Automated application deployment pipeline')
    
    parameters {
        choiceParam('ENVIRONMENT', ['dev', 'staging', 'prod'], 'Target environment')
        choiceParam('DEPLOYMENT_TYPE', ['rolling', 'blue-green', 'canary'], 'Deployment strategy')
        stringParam('APPLICATION_VERSION', 'latest', 'Application version to deploy')
        booleanParam('RUN_TESTS', true, 'Run automated tests after deployment')
        booleanParam('SECURITY_SCAN', true, 'Run security scan after deployment')
    }
    
    properties {
        githubProjectProperty {
            projectUrl('https://github.com/Dwalker0357/Optum_UK_AWS_Demo')
        }
        buildDiscarder {
            strategy {
                logRotator {
                    numToKeepStr('15')
                    daysToKeepStr('45')
                }
            }
        }
    }
    
    triggers {
        githubPush()
    }
    
    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/Dwalker0357/Optum_UK_AWS_Demo.git')
                        credentials('github-token')
                    }
                    branch('main')
                }
            }
            scriptPath('jenkins/pipelines/application.jenkinsfile')
            lightweight(true)
        }
    }
}

// Environment Provisioning Pipeline
pipelineJob('environment-provisioning') {
    displayName('Environment Provisioning Pipeline')
    description('Provision complete environments using Ansible and Terraform')
    
    parameters {
        choiceParam('OS_TYPE', ['amazon-linux-2', 'ubuntu-20.04', 'centos-8'], 'Operating System')
        choiceParam('INSTANCE_SIZE', ['t3.micro', 't3.small', 't3.medium', 't3.large'], 'Instance size')
        choiceParam('REGION', ['eu-west-1', 'us-east-1', 'us-west-2'], 'AWS Region')
        stringParam('ENVIRONMENT_NAME', '', 'Environment name (required)')
        booleanParam('INSTALL_DOCKER', true, 'Install Docker')
        booleanParam('CONFIGURE_MONITORING', true, 'Configure monitoring')
    }
    
    definition {
        cps {
            script('''
                pipeline {
                    agent {
                        label 'linux && ansible && terraform'
                    }
                    
                    environment {
                        AWS_DEFAULT_REGION = "${params.REGION}"
                        ENVIRONMENT_NAME = "${params.ENVIRONMENT_NAME}"
                    }
                    
                    stages {
                        stage('Validate Parameters') {
                            steps {
                                script {
                                    if (!params.ENVIRONMENT_NAME) {
                                        error("Environment name is required")
                                    }
                                    echo "Provisioning environment: ${params.ENVIRONMENT_NAME}"
                                    echo "OS: ${params.OS_TYPE}"
                                    echo "Instance Size: ${params.INSTANCE_SIZE}"
                                    echo "Region: ${params.REGION}"
                                }
                            }
                        }
                        
                        stage('Provision Infrastructure') {
                            steps {
                                dir('terraform') {
                                    sh """
                                        terraform init
                                        terraform plan \\
                                            -var="environment_name=${params.ENVIRONMENT_NAME}" \\
                                            -var="instance_type=${params.INSTANCE_SIZE}" \\
                                            -var="region=${params.REGION}" \\
                                            -var="os_type=${params.OS_TYPE}" \\
                                            -out=tfplan
                                        terraform apply tfplan
                                    """
                                }
                            }
                        }
                        
                        stage('Configure Environment') {
                            steps {
                                script {
                                    def inventory = sh(
                                        script: "terraform output -json instance_ips | jq -r '.[]'",
                                        returnStdout: true
                                    ).trim()
                                    
                                    writeFile file: 'ansible-inventory.ini', text: """
[servers]
${inventory}

[servers:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=/var/lib/jenkins/.ssh/id_rsa
"""
                                }
                                
                                sh """
                                    ansible-playbook -i ansible-inventory.ini \\
                                        playbooks/configure-environment.yml \\
                                        --extra-vars="install_docker=${params.INSTALL_DOCKER}" \\
                                        --extra-vars="configure_monitoring=${params.CONFIGURE_MONITORING}"
                                """
                            }
                        }
                        
                        stage('Verify Environment') {
                            steps {
                                sh """
                                    ansible-playbook -i ansible-inventory.ini \\
                                        playbooks/verify-environment.yml
                                """
                            }
                        }
                        
                        stage('Security Baseline') {
                            steps {
                                sh """
                                    ansible-playbook -i ansible-inventory.ini \\
                                        playbooks/security-baseline.yml
                                """
                            }
                        }
                    }
                    
                    post {
                        success {
                            echo "Environment ${params.ENVIRONMENT_NAME} provisioned successfully"
                            
                            // Trigger security scan
                            build job: 'security-scanning', parameters: [
                                string(name: 'TARGET_ENVIRONMENT', value: params.ENVIRONMENT_NAME),
                                string(name: 'SCAN_TYPE', value: 'basic')
                            ]
                        }
                        
                        failure {
                            echo "Environment provisioning failed"
                        }
                        
                        always {
                            archiveArtifacts artifacts: 'terraform/*.tfstate', allowEmptyArchive: true
                            cleanWs()
                        }
                    }
                }
            ''')
            sandbox(true)
        }
    }
}
APP_DSL

# Set ownership
chown -R "$JENKINS_USER:$JENKINS_USER" "$JENKINS_HOME/dsl-scripts"

echo "=== Pipeline configurations created successfully ==="
