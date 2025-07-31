import json
import boto3
import os
from datetime import datetime

def handler(event, context):
    """
    AWS Lambda function to respond to GuardDuty findings
    """
    
    # Initialize AWS clients
    sns = boto3.client('sns')
    ec2 = boto3.client('ec2')
    
    # Get environment variables
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    project_name = os.environ.get('PROJECT_NAME', 'optum-uk-demo')
    
    try:
        # Parse GuardDuty finding
        detail = event.get('detail', {})
        finding_id = detail.get('id', 'unknown')
        finding_type = detail.get('type', 'unknown')
        severity = detail.get('severity', 0)
        title = detail.get('title', 'GuardDuty Finding')
        description = detail.get('description', 'No description available')
        
        # Get affected resources
        resources = detail.get('service', {}).get('resourceRole', 'unknown')
        instance_details = detail.get('service', {}).get('remoteIpDetails', {})
        
        # Create alert message
        timestamp = datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
        
        message = f"""
🚨 GUARDDUTY SECURITY ALERT 🚨

Project: {project_name}
Time: {timestamp}
Severity: {severity}/10

Finding ID: {finding_id}
Type: {finding_type}
Title: {title}

Description:
{description}

Affected Resources: {resources}

Remote IP Details:
{json.dumps(instance_details, indent=2) if instance_details else 'Not available'}

Action Required:
1. Review the finding in GuardDuty console
2. Investigate affected resources
3. Implement remediation if necessary
4. Update security groups if needed

GuardDuty Console: https://console.aws.amazon.com/guardduty/
"""

        # Send SNS notification
        if sns_topic_arn:
            response = sns.publish(
                TopicArn=sns_topic_arn,
                Subject=f'🚨 GuardDuty Alert: {title}',
                Message=message
            )
            print(f"SNS notification sent: {response['MessageId']}")
        
        # Log the finding
        print(f"GuardDuty finding processed: {finding_id}")
        print(f"Severity: {severity}, Type: {finding_type}")
        
        # For high severity findings, consider automatic remediation
        if severity >= 7.0:
            print(f"High severity finding detected: {severity}")
            # Add automatic remediation logic here if needed
            # Example: Isolate instance, block IP, etc.
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'GuardDuty finding processed successfully',
                'finding_id': finding_id,
                'severity': severity
            })
        }
        
    except Exception as e:
        error_message = f"Error processing GuardDuty finding: {str(e)}"
        print(error_message)
        
        # Send error notification
        if sns_topic_arn:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject=f'❌ GuardDuty Lambda Error - {project_name}',
                Message=f"Error processing GuardDuty finding:\n\n{error_message}\n\nEvent:\n{json.dumps(event, indent=2)}"
            )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }
