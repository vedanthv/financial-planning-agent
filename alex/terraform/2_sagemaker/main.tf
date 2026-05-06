terraform {
  # Minimum Terraform version required to run this configuration
  required_version = ">= 1.5"
  
  # Providers are plugins Terraform uses to interact with cloud services
  required_providers {
    
    # AWS provider allows Terraform to create/manage AWS resources
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70" # Use AWS provider version 5.70 or compatible patch versions
    }
  }
  
  # Backend configuration determines where Terraform state is stored
  # Since no backend is configured here, Terraform uses LOCAL backend by default
  # State will be stored in terraform.tfstate in the current directory
  #
  # Terraform state contains:
  # - Resource IDs
  # - Infrastructure metadata
  # - Mapping between Terraform config and real AWS resources
  #
  # Usually terraform.tfstate is added to .gitignore because it may contain:
  # - Resource ARNs
  # - Sensitive values
  # - Infrastructure details
}

# Configure AWS provider
provider "aws" {

  # AWS region where all resources will be created
  # Example: us-east-1, us-west-2, ap-south-1
  #
  # Value comes from variables.tf or terraform.tfvars
  region = var.aws_region
}

# Data source = read existing information from AWS
# This does NOT create resources
#
# aws_caller_identity fetches details about the currently authenticated AWS user/role
#
# Useful values:
# - account_id
# - arn
# - user_id
#
# Example usage:
# data.aws_caller_identity.current.account_id
data "aws_caller_identity" "current" {}

# IAM Role for SageMaker
#
# SageMaker itself needs permissions to:
# - Pull Docker images
# - Access S3
# - Write logs
# - Create models/endpoints
#
# AWS services assume IAM roles temporarily using STS (Security Token Service)
resource "aws_iam_role" "sagemaker_role" {

  # Name of the IAM role in AWS
  name = "alex-sagemaker-role"

  # Trust policy (Assume Role Policy)
  #
  # This defines WHO can assume/use this role
  #
  # In this case:
  # - Service: sagemaker.amazonaws.com
  # - Meaning SageMaker service is allowed to use this role
  #
  # Without this policy:
  # SageMaker cannot use the role even if permissions exist
  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [
      {
        # sts:AssumeRole allows temporary role assumption
        Action = "sts:AssumeRole"

        Effect = "Allow"

        Principal = {
          # AWS SageMaker service principal
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy to the IAM role
#
# Managed policy = predefined AWS permissions bundle
#
# AmazonSageMakerFullAccess gives broad SageMaker permissions
#
# This is easier for development/testing
# In production, least-privilege custom policies are preferred
resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {

  # IAM role name to attach policy to
  role = aws_iam_role.sagemaker_role.name

  # ARN of AWS managed policy
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# SageMaker Model Resource
#
# This defines:
# - Which container/image to run
# - Which model should be loaded
# - Which IAM role SageMaker should use
#
# IMPORTANT:
# This does NOT deploy the model yet
# It only registers model metadata in SageMaker
resource "aws_sagemaker_model" "embedding_model" {

  # Name of model inside SageMaker
  name = "alex-embedding-model"

  # IAM role SageMaker uses while running the container
  execution_role_arn = aws_iam_role.sagemaker_role.arn

  # Primary inference container configuration
  primary_container {

    # Docker image URI
    #
    # Usually a HuggingFace inference container
    # Example:
    # 763104351884.dkr.ecr.us-east-1.amazonaws.com/huggingface-pytorch-inference:...
    image = var.sagemaker_image_uri

    # Environment variables passed into the container
    environment = {

      # HuggingFace model to download/load
      #
      # Example:
      # sentence-transformers/all-MiniLM-L6-v2
      HF_MODEL_ID = var.embedding_model_name

      # Task type for HuggingFace inference toolkit
      #
      # feature-extraction = generate embeddings/vectors
      HF_TASK = "feature-extraction"
    }
  }

  # Ensure policy attachment completes before model creation
  #
  # This avoids IAM propagation timing issues
  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

# SageMaker Endpoint Configuration
#
# Endpoint config defines HOW the model should be deployed
#
# Think of it as deployment settings:
# - instance/serverless type
# - scaling
# - traffic routing
resource "aws_sagemaker_endpoint_configuration" "serverless_config" {

  name = "alex-embedding-serverless-config"

  # Production variants define model deployment settings
  production_variants {

    # Which model to deploy
    model_name = aws_sagemaker_model.embedding_model.name
    
    # Serverless inference configuration
    #
    # AWS provisions compute automatically on demand
    # No EC2 instance management required
    #
    # Good for:
    # - low traffic
    # - dev/testing
    # - cost optimization
    serverless_config {

      # RAM allocated to endpoint container
      #
      # Larger models need more memory
      #
      # 3072 MB = 3 GB RAM
      memory_size_in_mb = 3072

      # Maximum simultaneous requests
      #
      # Higher concurrency:
      # - handles more parallel traffic
      # - increases resource usage/quota requirements
      #
      # Reduced to 2 to avoid AWS quota errors
      max_concurrency = 2
    }
  }
}

# Artificial wait/delay resource
#
# WHY THIS EXISTS:
#
# IAM changes in AWS are eventually consistent
# Meaning:
# - role/policy may be created
# - but not immediately usable everywhere
#
# SageMaker often fails if role propagation is incomplete
#
# This resource simply waits 15 seconds
resource "time_sleep" "wait_for_iam_propagation" {

  # Wait only after policy attachment completes
  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
  
  # Duration to wait
  create_duration = "15s"
}

# SageMaker Endpoint
#
# This is the ACTUAL deployed inference endpoint
#
# Once created:
# - AWS provisions infrastructure
# - model container starts
# - endpoint becomes callable via HTTPS/API
#
# Your applications will invoke THIS endpoint
resource "aws_sagemaker_endpoint" "embedding_endpoint" {

  # Endpoint name
  name = "alex-embedding-endpoint"

  # Which deployment configuration to use
  endpoint_config_name = aws_sagemaker_endpoint_configuration.serverless_config.name
  
  # Ensure IAM propagation wait finishes first
  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}