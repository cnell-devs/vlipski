terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
}

# S3 Bucket for video storage
resource "aws_s3_bucket" "video_bucket" {
  bucket = "vlipski-video-storage"
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "video_bucket_versioning" {
  bucket = aws_s3_bucket.video_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "video_bucket_encryption" {
  bucket = aws_s3_bucket.video_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach Basic Execution Role to Lambda
resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "lambda_basic_execution"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for S3 access
resource "aws_iam_policy" "lambda_s3_policy" {
  name = "lambda_s3_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.video_bucket.arn}/*",
          aws_s3_bucket.video_bucket.arn
        ]
      }
    ]
  })
}

# Attach S3 policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_s3_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "request_lambda" {
  function_name = "UserRequestLambda"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "lambda_function.lambda_handler"
  timeout       = 300  # 5 minutes timeout for video processing
  memory_size   = 1024 # 1GB memory for video processing

  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.video_bucket.id
    }
  }
}

resource "aws_apigatewayv2_api" "gateway" {
  name          = "vlipski-http-api"
  protocol_type = "HTTP"

   cors_configuration {
    allow_origins = ["http://localhost:5173", "http://127.0.0.1:5173"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key", "X-Amz-Security-Token"]
    allow_credentials = true
    max_age = 300
  }
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.gateway.id
  route_key = "$default"
}

# API Integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.gateway.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.request_lambda.invoke_arn
}

# API Route (ANY /hello)
resource "aws_apigatewayv2_route" "hello_route" {
  api_id    = aws_apigatewayv2_api.gateway.id
  route_key = "ANY /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Deploy API Gateway
resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.gateway.id
  name        = "$default"
  auto_deploy = true
}

# API Route (POST /mypost)
resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.gateway.id
  route_key = "POST /mypost"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Permission for API Gateway to Invoke Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.request_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.gateway.execution_arn}/*/*"
}

# Output API Endpoint
output "api_url" {
  description = "Invoke URL for API Gateway"
  value       = aws_apigatewayv2_api.gateway.api_endpoint
}
