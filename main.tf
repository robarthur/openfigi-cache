# Require TF version to be same as or greater than 0.12.13
terraform {
  required_version = ">=1.2.5"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.22.0"
    }
  }
  # For now lets just use local state
  #backend "s3" {
  #  bucket         = "bucket"
  #  key            = "terraform.tfstate"
  #  region         = "us-east-1"
  #  dynamodb_table = "aws-locks"
  #  encrypt        = true
  #}
}

# Download any stable version in AWS provider of 4.22.0 or higher in 4.22.0 train
provider "aws" {
  region  = "us-east-1"
}

#
# VPC Module
#
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "open-figi-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  private_subnets  = ["10.0.0.0/24","10.0.2.0/24","10.0.3.0/24"]

  enable_ipv6          = false
  enable_dns_hostnames = true
  enable_nat_gateway = true
  single_nat_gateway  = true
}


#
# Elasticache Resources
#

resource "aws_elasticache_cluster" "openfigi_cache" {
  cluster_id           = "openfigi-cache"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.elasticache.id]
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  engine_version       = "6.2"
  port                 = 6379
}

resource "aws_elasticache_subnet_group" "redis" {
  name        = "openfigi-cache-subnet-group"
  subnet_ids  = module.vpc.private_subnets
}

resource "aws_security_group" "elasticache" {
  name        = "elasticache"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "Redis from VPC"
    from_port        = 6379
    to_port          = 6379
    protocol         = "tcp"
    cidr_blocks      = module.vpc.private_subnets_cidr_blocks
  }

  ingress {
    description      = "Redis from Lambda"
    from_port        = 6379
    to_port          = 6379
    protocol         = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

#
# Lambda Resources
#

resource "aws_s3_bucket" "lambda_deploy" {
  bucket_prefix = "lambda-deploy"
}

resource "aws_s3_bucket_acl" "lambda_deploy" {
  bucket = aws_s3_bucket.lambda_deploy.id
  acl    = "private"
}

resource "aws_s3_object" "open_figi_cache_deploy" {
  bucket = aws_s3_bucket.lambda_deploy.id
  key    = "mappings.zip"
  source = "deploy/mappings.zip"
  source_hash = filemd5("deploy/mappings.zip")
}

resource "aws_s3_object" "keys_deploy" {
  bucket = aws_s3_bucket.lambda_deploy.id
  key    = "keys.zip"
  source = "deploy/keys.zip"
  source_hash = filemd5("deploy/keys.zip")
}

resource "aws_s3_bucket_public_access_block" "lambda_deploy" {
  bucket = aws_s3_bucket.lambda_deploy.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_lambda_function" "open_figi_cache" {
  
  depends_on = [
    aws_s3_object.open_figi_cache_deploy
  ]
  
  function_name = "OpenFigiCache"

  # The bucket name as created earlier with "aws s3api create-bucket"
  s3_bucket = aws_s3_bucket.lambda_deploy.id
  s3_key    = aws_s3_object.open_figi_cache_deploy.key
  source_code_hash = filebase64sha256("deploy/mappings.zip")

  # "main" is the filename within the zip file (main.js) and "handler"
  # is the name of the property under which the handler function was
  # exported in that file.
  handler = "mappings.lambda_handler"
  runtime = "python3.9"
  # The openfigi api can be slow to respond
  timeout = 10

  role = "${aws_iam_role.lambda_exec.arn}"

  vpc_config {
    # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }


  environment {
    variables = {
      API_KEY = var.api_key
      REDIS_ENDPOINT = aws_elasticache_cluster.openfigi_cache.cache_nodes[0].address
      REDIS_PORT = aws_elasticache_cluster.openfigi_cache.cache_nodes[0].port
    }
  }
}

resource "aws_lambda_function" "keys" {
  
  depends_on = [
    aws_s3_object.keys_deploy
  ]
  
  function_name = "OpenFigiKeys"

  # The bucket name as created earlier with "aws s3api create-bucket"
  s3_bucket = aws_s3_bucket.lambda_deploy.id
  s3_key    = aws_s3_object.keys_deploy.key
  source_code_hash = filebase64sha256("deploy/keys.zip")

  # "main" is the filename within the zip file (main.js) and "handler"
  # is the name of the property under which the handler function was
  # exported in that file.
  handler = "keys.lambda_handler"
  runtime = "python3.9"

  role = "${aws_iam_role.lambda_exec.arn}"

  vpc_config {
    # Every subnet should be able to reach an EFS mount target in the same Availability Zone. Cross-AZ mounts are not permitted.
    subnet_ids         = module.vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }


  environment {
    variables = {
      API_KEY = var.api_key
      REDIS_ENDPOINT = aws_elasticache_cluster.openfigi_cache.cache_nodes[0].address
      REDIS_PORT = aws_elasticache_cluster.openfigi_cache.cache_nodes[0].port
    }
  }
}


resource "aws_security_group" "lambda" {
  name        = "lambda"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "open_figi_cache" {
  name = "/aws/lambda/${aws_lambda_function.open_figi_cache.function_name}"

  retention_in_days = 7
}

#
# API Gateway Resources
#

resource "aws_apigatewayv2_api" "lambda" {
  name          = "open_figi_cache"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "v3"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "open_figi_cache" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.open_figi_cache.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_integration" "keys" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.keys.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "open_figi_cache" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /mapping"
  target    = "integrations/${aws_apigatewayv2_integration.open_figi_cache.id}"
}

resource "aws_apigatewayv2_route" "keys_get" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /keys/{key}"
  target    = "integrations/${aws_apigatewayv2_integration.keys.id}"
}

resource "aws_apigatewayv2_route" "keys_get_all" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /keys"
  target    = "integrations/${aws_apigatewayv2_integration.keys.id}"
}

resource "aws_apigatewayv2_route" "keys_delete" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "DELETE /keys/{key}"
  target    = "integrations/${aws_apigatewayv2_integration.keys.id}"
}

resource "aws_apigatewayv2_route" "keys_delete_all" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "DELETE /keys"
  target    = "integrations/${aws_apigatewayv2_integration.keys.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 7
}

resource "aws_lambda_permission" "api_gw" {
  for_each = toset([aws_lambda_function.open_figi_cache.function_name, aws_lambda_function.keys.function_name])
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}


#
# IAM Resources 
#

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

