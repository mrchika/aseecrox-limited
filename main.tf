# ==========================================================================
# 1. PROVIDER & AWS CORE ENVIRONMENT DEFINITION
# ==========================================================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

variable "receiver_email" {
  description = "Verified address that receives new client inquiries."
  type        = string
  default     = "aseecroxlimited@gmail.com"
}

variable "sender_email" {
  description = "Verified SES identity used as the From address."
  type        = string
  default     = "aseecroxlimited@gmail.com"
}

provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

# ==========================================================================
# 2. AMAZON DYNAMODB TABLE STRUCTURAL SPECIFICATION
# ==========================================================================
resource "aws_dynamodb_table" "aseecrox_inquiries" {
  name         = "aseecrox-inquiries-db-v3" # Fresh name to bypass any conflicts
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"
  range_key    = "timestamp"

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }
}

# ==========================================================================
# 3. AWS IAM SECURITY ROLES & CORRESPONDING POLICY ATTACHMENTS
# ==========================================================================
resource "aws_iam_role" "lambda_exec_role" {
  name = "aseecrox-lambda-execution-role-v3" # Fresh name to bypass conflicts

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_db_write_policy" {
  name = "aseecrox-lambda-dynamodb-policy-v3"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.aseecrox_inquiries.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ==========================================================================
# 4. AWS LAMBDA RUNTIME ARCHITECTURE PROVISIONING
# ==========================================================================
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "aseecrox_form_handler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "aseecrox-form-handler-v3"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10

  environment {
    variables = {
      DB_TABLE       = aws_dynamodb_table.aseecrox_inquiries.name
      RECEIVER_EMAIL = var.receiver_email
      SENDER_EMAIL   = var.sender_email
    }
  }
}

# ==========================================================================
# 5. SES EMAIL DELIVERY
# ==========================================================================
resource "aws_iam_role_policy" "lambda_email_policy" {
  name = "aseecrox-lambda-email-policy-v3"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

# ============================================================================
# 6. API GATEWAY PUBLIC FORM ENDPOINT
# ============================================================================
resource "aws_api_gateway_rest_api" "aseecrox_api" {
  name = "aseecrox-client-inquiries"
}

resource "aws_api_gateway_resource" "contact" {
  rest_api_id = aws_api_gateway_rest_api.aseecrox_api.id
  parent_id   = aws_api_gateway_rest_api.aseecrox_api.root_resource_id
  path_part   = "contact"
}

resource "aws_api_gateway_method" "contact_post" {
  rest_api_id   = aws_api_gateway_rest_api.aseecrox_api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "contact_post" {
  rest_api_id             = aws_api_gateway_rest_api.aseecrox_api.id
  resource_id             = aws_api_gateway_resource.contact.id
  http_method             = aws_api_gateway_method.contact_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.aseecrox_form_handler.invoke_arn
}

resource "aws_api_gateway_method" "contact_options" {
  rest_api_id   = aws_api_gateway_rest_api.aseecrox_api.id
  resource_id   = aws_api_gateway_resource.contact.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "contact_options" {
  rest_api_id = aws_api_gateway_rest_api.aseecrox_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{ \"statusCode\": 200 }"
  }
}

resource "aws_api_gateway_method_response" "contact_options" {
  rest_api_id = aws_api_gateway_rest_api.aseecrox_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "contact_options" {
  rest_api_id = aws_api_gateway_rest_api.aseecrox_api.id
  resource_id = aws_api_gateway_resource.contact.id
  http_method = aws_api_gateway_method.contact_options.http_method
  status_code = aws_api_gateway_method_response.contact_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aseecrox_form_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.aseecrox_api.execution_arn}/*/*/contact"
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.aseecrox_api.id

  depends_on = [
    aws_api_gateway_integration.contact_post,
    aws_api_gateway_integration_response.contact_options
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.aseecrox_api.id
  deployment_id = aws_api_gateway_deployment.prod.id
  stage_name    = "prod"
}

output "api_endpoint" {
  value       = "https://${aws_api_gateway_rest_api.aseecrox_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/contact"
  description = "Set this value as AWS_API_ENDPOINT in index.html."
}