#!/usr/bin/env python3
"""
Terraform Drift Detection Lambda Function
Triggers Jenkins terraform plan jobs for drift detection
"""

import boto3
import json
import logging
import os
import requests
from typing import Dict, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context) -> Dict:
    """
    Main Lambda handler for drift detection
    """
    try:
        # Get environment variables
        jenkins_url = os.environ['JENKINS_URL']
        jenkins_user = os.environ['JENKINS_USER'] 
        jenkins_token = os.environ['JENKINS_TOKEN']
        s3_bucket = os.environ['S3_BUCKET']
        sns_topic_arn = os.environ['SNS_TOPIC_ARN']
        
        logger.info("Starting drift detection scan")
        
        # Get list of environments from S3 state bucket
        environments = get_environments_from_s3(s3_bucket)
        logger.info(f"Found environments: {environments}")
        
        # Trigger Jenkins drift detection for each environment
        results = []
        for env in environments:
            result = trigger_jenkins_drift_check(
                jenkins_url, jenkins_user, jenkins_token, env
            )
            results.append(result)
            
        # Send summary notification
        send_notification(sns_topic_arn, results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Drift detection initiated successfully',
                'environments_checked': len(environments),
                'results': results
            })
        }
        
    except Exception as e:
        logger.error(f"Error in drift detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def get_environments_from_s3(bucket_name: str) -> List[str]:
    """
    Get list of environments by examining S3 state bucket structure
    """
    s3_client = boto3.client('s3')
    environments = []
    
    try:
        # List objects in the state bucket
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Delimiter='/'
        )
        
        # Extract environment names from folder structure
        if 'CommonPrefixes' in response:
            for prefix in response['CommonPrefixes']:
                env_name = prefix['Prefix'].strip('/')
                if env_name and env_name not in ['logs', 'backups']:
                    environments.append(env_name)
                    
        # Fallback to default environments if none found
        if not environments:
            environments = ['uat', 'dev']
            
    except Exception as e:
        logger.warning(f"Could not list S3 environments: {e}")
        environments = ['uat', 'dev']  # Default fallback
        
    return environments

def trigger_jenkins_drift_check(jenkins_url: str, username: str, token: str, environment: str) -> Dict:
    """
    Trigger Jenkins drift detection job for specific environment
    """
    try:
        # Jenkins job URL for drift detection
        job_url = f"{jenkins_url}/job/Terraform-Drift-Detection/buildWithParameters"
        
        # Job parameters
        params = {
            'ENV': environment,
            'DRIFT_CHECK_ONLY': 'true'
        }
        
        # Make request to Jenkins
        auth = (username, token)
        response = requests.post(
            job_url,
            data=params,
            auth=auth,
            timeout=30
        )
        
        if response.status_code in [200, 201]:
            logger.info(f"Successfully triggered drift check for {environment}")
            return {
                'environment': environment,
                'status': 'triggered',
                'jenkins_response': response.status_code
            }
        else:
            logger.error(f"Failed to trigger drift check for {environment}: {response.status_code}")
            return {
                'environment': environment,
                'status': 'failed',
                'error': f"HTTP {response.status_code}"
            }
            
    except Exception as e:
        logger.error(f"Error triggering Jenkins job for {environment}: {e}")
        return {
            'environment': environment,
            'status': 'error',
            'error': str(e)
        }

def send_notification(sns_topic_arn: str, results: List[Dict]):
    """
    Send drift detection summary via SNS
    """
    try:
        sns_client = boto3.client('sns')
        
        # Prepare notification message
        total_envs = len(results)
        successful = len([r for r in results if r['status'] == 'triggered'])
        failed = total_envs - successful
        
        message = {
            'summary': f"Drift detection initiated for {total_envs} environments",
            'successful': successful,
            'failed': failed,
            'details': results
        }
        
        # Send SNS notification
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject='Terraform Drift Detection Summary',
            Message=json.dumps(message, indent=2)
        )
        
        logger.info("Notification sent successfully")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {e}")
