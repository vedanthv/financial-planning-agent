terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Using local backend - state will be stored in terraform.tfstate in this directory
  # This is automatically gitignored for security
}

provider "aws" {
  region = var.aws_region
}

# Data source for current caller identity
data "aws_caller_identity" "current" {}

# ========================================
# S3 Vectors Bucket
# ========================================

resource "aws_s3_bucket" "vectors" {
  bucket = "alex-vectors-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Project = "alex"
    Part    = "3"
  }
}

resource "aws_s3_bucket_versioning" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vectors" {
  bucket = aws_s3_bucket.vectors.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ========================================
# Lambda Function for Ingestion
# ========================================

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "alex-ingest-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Project = "alex"
    Part    = "3"
  }
}

# Lambda policy for S3 Vectors and SageMaker
resource "aws_iam_role_policy" "lambda_policy" {
  name = "alex-ingest-lambda-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.vectors.arn,
          "${aws_s3_bucket.vectors.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:InvokeEndpoint"
        ]
        Resource = "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:endpoint/${var.sagemaker_endpoint_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "s3vectors:PutVectors",
          "s3vectors:QueryVectors",
          "s3vectors:GetVectors",
          "s3vectors:DeleteVectors"
        ]
        Resource = "arn:aws:s3vectors:${var.aws_region}:${data.aws_caller_identity.current.account_id}:bucket/${aws_s3_bucket.vectors.id}/index/*"
      }
    ]
  })
}

# =========================
# AWS Lambda Function
# =========================
#
# This resource creates an AWS Lambda function.
#
# Lambda = serverless compute service
#
# AWS automatically:
# - provisions infrastructure
# - runs code on demand
# - scales automatically
# - manages servers
#
# This particular Lambda is responsible for:
# - ingesting data
# - generating embeddings
# - storing vectors in S3 vectors bucket

resource "aws_lambda_function" "ingest" {

  # Actual Lambda function name in AWS
  #
  # This is what appears in:
  # AWS Console -> Lambda
  #
  # NOT the Terraform resource name
  function_name = "alex-ingest"

  # IAM role ARN assumed by Lambda during execution
  #
  # Lambda needs permissions to:
  # - access S3
  # - invoke SageMaker endpoint
  # - write CloudWatch logs
  #
  # ARN example:
  # arn:aws:iam::123456789012:role/alex-lambda-role
  role = aws_iam_role.lambda_role.arn
  
  # =========================
  # DEPLOYMENT PACKAGE
  # =========================
  #
  # Lambda code must be uploaded as:
  # - ZIP file
  # OR
  # - container image
  #
  # This project uses ZIP deployment

  # Path to deployment ZIP package
  #
  # path.module =
  # current Terraform module directory
  #
  # ../../backend/ingest/lambda_function.zip
  # navigates relative to Terraform module location
  #
  # ZIP contains:
  # - Python code
  # - dependencies
  # - Lambda handler files
  #
  # Example contents:
  #
  # lambda_function.zip
  # ├── ingest_s3vectors.py
  # ├── boto3/
  # ├── requests/
  # └── sentence_transformers/
  #
  # Terraform uploads this ZIP to Lambda
  filename = "${path.module}/../../backend/ingest/lambda_function.zip"

  # Hash of deployment package
  #
  # WHY IMPORTANT:
  # Terraform needs a way to detect code changes
  #
  # If ZIP contents change:
  # - hash changes
  # - Terraform updates Lambda automatically
  #
  # filebase64sha256():
  # computes SHA256 hash of ZIP file
  #
  # fileexists():
  # prevents Terraform failure if ZIP does not exist yet
  #
  # If file missing:
  # source_code_hash = null
  #
  # This is useful during initial setup
  source_code_hash = fileexists(
    "${path.module}/../../backend/ingest/lambda_function.zip"
    ) ? filebase64sha256(
      "${path.module}/../../backend/ingest/lambda_function.zip"
    ) : null
  
  # =========================
  # HANDLER CONFIGURATION
  # =========================

  # Lambda handler entry point
  #
  # Format:
  # <python_file>.<function_name>
  #
  # Example:
  #
  # File:
  # ingest_s3vectors.py
  #
  # Function:
  # def lambda_handler(event, context):
  #
  # Full handler:
  # ingest_s3vectors.lambda_handler
  #
  # Lambda runtime imports this automatically
  handler = "ingest_s3vectors.lambda_handler"

  # Python runtime environment
  #
  # AWS provides managed runtime container
  #
  # Includes:
  # - Python interpreter
  # - Lambda runtime interface
  runtime = "python3.12"

  # Maximum execution time in seconds
  #
  # If Lambda exceeds this:
  # AWS forcibly terminates execution
  #
  # Common causes:
  # - slow inference
  # - network delays
  # - large file processing
  timeout = 60

  # Memory allocated to Lambda in MB
  #
  # Lambda CPU power scales WITH memory
  #
  # More memory:
  # - faster execution
  # - higher cost
  #
  # 512 MB is moderate allocation
  memory_size = 512
  
  # =========================
  # ENVIRONMENT VARIABLES
  # =========================
  #
  # Key-value variables injected into Lambda runtime
  #
  # Accessible in Python via:
  #
  # os.environ["VARIABLE_NAME"]
  #
  # Useful for:
  # - configuration
  # - endpoint names
  # - bucket names
  # - feature flags

  environment {

    variables = {

      # S3 bucket storing vector embeddings
      #
      # aws_s3_bucket.vectors.id
      # references bucket resource dynamically
      #
      # Prevents hardcoding bucket names
      VECTOR_BUCKET = aws_s3_bucket.vectors.id

      # SageMaker inference endpoint name
      #
      # Lambda uses this to invoke embedding model
      #
      # Example:
      # alex-embedding-endpoint
      SAGEMAKER_ENDPOINT = var.sagemaker_endpoint_name
    }
  }
  
  # =========================
  # RESOURCE TAGS
  # =========================
  #
  # AWS tags are metadata labels
  #
  # Useful for:
  # - cost tracking
  # - organization
  # - filtering resources
  # - automation
  #
  # Example:
  # AWS Cost Explorer can group by tags
  tags = {

    # Project/application name
    Project = "alex"

    # Architecture/project phase identifier
    Part = "3"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/alex-ingest"
  retention_in_days = 7
  
  tags = {
    Project = "alex"
    Part    = "3"
  }
}

# ========================================
# API Gateway
# ========================================
#
# API Gateway acts as the PUBLIC ENTRY POINT
# for your backend system.
#
# Client Flow:
#
# Frontend/App
#      ↓
# API Gateway
#      ↓
# Lambda Function
#      ↓
# SageMaker + S3
#
# API Gateway responsibilities:
# - expose HTTPS endpoints
# - routing requests
# - authentication
# - throttling/rate limiting
# - API keys
# - request/response handling
# - monitoring/logging

# ========================================
# REST API
# ========================================

# Creates the top-level API Gateway REST API
#
# Think of this as the API "container"
#
# Example final URL:
# https://abc123.execute-api.us-east-1.amazonaws.com/prod/ingest
#
# Without this resource:
# no API exists at all
resource "aws_api_gateway_rest_api" "api" {

  # API name shown in AWS Console
  name = "alex-api"

  # Description metadata
  description = "Alex Financial Planner API"
  
  # Endpoint configuration determines HOW API is exposed
  endpoint_configuration {

    # REGIONAL endpoint:
    #
    # API deployed in one AWS region
    #
    # Best default choice
    #
    # Other options:
    #
    # EDGE
    # -> CloudFront optimized globally
    #
    # PRIVATE
    # -> internal VPC-only API
    types = ["REGIONAL"]
  }
  
  # AWS resource tags
  tags = {
    Project = "alex"
    Part    = "3"
  }
}

# ========================================
# API RESOURCE (URL PATH)
# ========================================

# Creates URL path resource
#
# Example:
# /ingest
#
# APIs are hierarchical trees:
#
# Root
# ├── /ingest
# ├── /search
# └── /users
#
# This resource defines ONLY the path
# not HTTP methods yet
resource "aws_api_gateway_resource" "ingest" {

  # Which API this path belongs to
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Parent resource ID
  #
  # root_resource_id means:
  # attach directly under "/"
  #
  # Result:
  # /ingest
  #
  # If parent was /users:
  # result could become:
  # /users/profile
  parent_id = aws_api_gateway_rest_api.api.root_resource_id

  # URL path segment
  path_part = "ingest"
}

# ========================================
# API METHOD
# ========================================

# Defines HTTP operation allowed on resource
#
# Resource alone is not enough
#
# Example:
# /ingest
#
# must also specify:
# GET?
# POST?
# PUT?
# DELETE?
#
# This creates:
# POST /ingest
resource "aws_api_gateway_method" "ingest_post" {

  # Which API
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Which resource/path
  resource_id = aws_api_gateway_resource.ingest.id

  # HTTP method
  #
  # POST usually used for:
  # - submitting data
  # - creating resources
  # - inference requests
  http_method = "POST"

  # Authentication type
  #
  # NONE:
  # no IAM/Cognito/custom auth
  #
  # Alternatives:
  # AWS_IAM
  # COGNITO_USER_POOLS
  # CUSTOM
  authorization = "NONE"

  # Require API key
  #
  # Client must provide:
  # x-api-key header
  #
  # Helps:
  # - control access
  # - track usage
  # - enforce quotas
  api_key_required = true
}

# ========================================
# LAMBDA INTEGRATION
# ========================================

# Connects API Gateway TO Lambda
#
# VERY IMPORTANT:
#
# Without integration:
# API endpoint exists
# BUT does nothing
#
# This defines backend target
resource "aws_api_gateway_integration" "lambda" {

  # API reference
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Resource/path reference
  resource_id = aws_api_gateway_resource.ingest.id

  # Method reference
  http_method = aws_api_gateway_method.ingest_post.http_method
  
  # HTTP method used internally
  #
  # Lambda integrations always use POST internally
  # even if external API method is GET
  integration_http_method = "POST"

  # Integration type
  #
  # AWS_PROXY = Lambda Proxy Integration
  #
  # API Gateway forwards:
  # - headers
  # - body
  # - query params
  # - request context
  #
  # directly to Lambda event object
  #
  # Lambda returns full HTTP response
  #
  # Modern recommended approach
  type = "AWS_PROXY"

  # Lambda invoke ARN
  #
  # Tells API Gateway WHICH Lambda to invoke
  #
  # invoke_arn is special invocation endpoint ARN
  uri = aws_lambda_function.ingest.invoke_arn
}

# ========================================
# LAMBDA INVOCATION PERMISSION
# ========================================

# VERY IMPORTANT SECURITY RESOURCE
#
# By default:
# API Gateway CANNOT invoke Lambda
#
# Even if integration exists
#
# This explicitly grants permission
resource "aws_lambda_permission" "api_gateway" {

  # Statement identifier
  statement_id = "AllowAPIGatewayInvoke"

  # Allowed action
  #
  # lambda:InvokeFunction =
  # permission to execute Lambda
  action = "lambda:InvokeFunction"

  # Which Lambda function
  function_name = aws_lambda_function.ingest.function_name

  # Who is allowed
  #
  # API Gateway AWS service principal
  principal = "apigateway.amazonaws.com"

  # Restrict which API Gateway ARN can invoke
  #
  # Security best practice
  #
  # execution_arn example:
  # arn:aws:execute-api:us-east-1:123456789:abc123
  #
  # /*/* means:
  # any stage
  # any method
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ========================================
# API DEPLOYMENT
# ========================================

# API Gateway changes are NOT live automatically
#
# Deployment creates SNAPSHOT of API configuration
#
# Think of it like:
# "publish API changes"
#
# Without deployment:
# API endpoint won't work publicly
resource "aws_api_gateway_deployment" "api" {

  # Which API to deploy
  rest_api_id = aws_api_gateway_rest_api.api.id
  
  # Force redeployment when API resources change
  #
  # IMPORTANT Terraform workaround
  #
  # API Gateway deployments are immutable snapshots
  #
  # Terraform otherwise may NOT detect changes
  #
  # sha1(jsonencode(...)) creates hash
  # based on resource IDs
  #
  # If:
  # - method changes
  # - integration changes
  # - resource changes
  #
  # hash changes
  # -> deployment recreated
  triggers = {

    redeployment = sha1(jsonencode([

      # Resource/path dependency
      aws_api_gateway_resource.ingest.id,

      # Method dependency
      aws_api_gateway_method.ingest_post.id,

      # Integration dependency
      aws_api_gateway_integration.lambda.id,
    ]))
  }
  
  lifecycle {

    # Create new deployment BEFORE deleting old one
    #
    # Prevents temporary downtime
    create_before_destroy = true
  }
}

# ========================================
# API STAGE
# ========================================

# Stage = environment/version of deployed API
#
# Common stages:
# - dev
# - test
# - staging
# - prod
#
# Final URL structure:
#
# https://api-id.execute-api.region.amazonaws.com/prod/ingest
#
# "prod" comes from stage name
resource "aws_api_gateway_stage" "api" {

  # Which deployment snapshot to expose
  deployment_id = aws_api_gateway_deployment.api.id

  # Which API
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Stage/environment name
  stage_name = "prod"
  
  tags = {
    Project = "alex"
    Part    = "3"
  }
}

# ========================================
# API KEY
# ========================================

# Creates API key for clients
#
# Client must send:
#
# x-api-key: <key>
#
# Used for:
# - controlling access
# - tracking consumers
# - quotas/throttling
#
# NOT strong authentication
# mainly usage management
resource "aws_api_gateway_api_key" "api_key" {

  # API key name in AWS Console
  name = "alex-api-key"
  
  tags = {
    Project = "alex"
    Part    = "3"
  }
}

# ========================================
# USAGE PLAN
# ========================================

# Usage plan defines:
# - quotas
# - throttling
# - rate limits
#
# API keys are attached to usage plans
#
# Prevents:
# - abuse
# - accidental overload
# - runaway costs
resource "aws_api_gateway_usage_plan" "plan" {

  name = "alex-usage-plan"
  
  # Associate usage plan with API stage
  api_stages {

    # Which API
    api_id = aws_api_gateway_rest_api.api.id

    # Which stage
    stage = aws_api_gateway_stage.api.stage_name
  }
  
  # Monthly quota limits
  quota_settings {

    # Maximum requests/month
    limit = 10000

    # Reset period
    period = "MONTH"
  }
  
  # Request throttling settings
  throttle_settings {

    # Sustained requests per second
    #
    # Average allowed throughput
    rate_limit = 100

    # Temporary burst capacity
    #
    # Handles traffic spikes briefly
    burst_limit = 200
  }
}

# ========================================
# USAGE PLAN KEY ASSOCIATION
# ========================================

# Connects:
# API Key <-> Usage Plan
#
# Without this:
# API key exists
# BUT has no permissions/limits attached
resource "aws_api_gateway_usage_plan_key" "plan_key" {

  # API key ID
  key_id = aws_api_gateway_api_key.api_key.id

  # Key type
  #
  # API_KEY is standard API Gateway key type
  key_type = "API_KEY"

  # Which usage plan this key belongs to
  usage_plan_id = aws_api_gateway_usage_plan.plan.id
}