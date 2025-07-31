import json
import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda function to start/stop Nessus Auto Scaling Group for demo mode
    """
    try:
        # Initialize AWS clients
        autoscaling = boto3.client('autoscaling')
        
        # Get parameters from environment and event
        asg_name = os.environ.get('ASG_NAME')
        action = event.get('action', 'start')
        desired_capacity = event.get('desired_capacity', 1)
        
        if not asg_name:
            raise ValueError("ASG_NAME environment variable not set")
        
        logger.info(f"Processing {action} action for ASG: {asg_name}")
        
        if action == 'start':
            # Start the Auto Scaling Group
            response = autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=desired_capacity,
                MinSize=1 if desired_capacity > 0 else 0
            )
            logger.info(f"Started ASG {asg_name} with desired capacity: {desired_capacity}")
            
        elif action == 'stop':
            # Stop the Auto Scaling Group
            response = autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=0,
                MinSize=0
            )
            logger.info(f"Stopped ASG {asg_name}")
            
        else:
            raise ValueError(f"Invalid action: {action}. Must be 'start' or 'stop'")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully {action}ed Nessus scanners',
                'asg_name': asg_name,
                'action': action,
                'desired_capacity': desired_capacity if action == 'start' else 0
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process scheduler request'
            })
        }
