# Terraform Remote State Backend Configuration
# S3 Backend for storing Terraform state with DynamoDB locking
# Backend configuration is provided via Jenkins pipeline or CLI
# Example: terraform init -backend-config="bucket=optum-dev-demo-terraform-state"

terraform {
  backend "s3" {
    # bucket, key, region, and dynamodb_table are configured via backend-config flags
    # This allows for environment-specific state management with locking
    encrypt = true
  }
}
