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
# Elasticache Resources
#

resource "aws_elasticache_cluster" "example" {
  cluster_id           = "openfigi-cache"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  engine_version       = "6.2"
  port                 = 6379
}

#
# Lambda Resources
#

resource "null_resource" "package_lambda" {
  
    provisioner "local-exec" {
    command = "rm -rf deploy/"
  }
  
  provisioner "local-exec" {
    command = "pip install -r ./requirements.txt -t deploy/source/ --upgrade"
  }

  provisioner "local-exec" {
    command = "cp python/src/main.py deploy/source/main.py"
  }

  triggers = {
    dependencies_versions = filemd5("./requirements.txt"),
    source_version  = filemd5("python/src/main.py"),
  }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir = "deploy/source/"
  output_path = "deploy/open_figi_cache.zip"
}

resource "aws_s3_bucket" "lambda_deploy" {
  bucket_prefix = "lambda-deploy"
}

resource "aws_s3_bucket_acl" "lambda_deploy" {
  bucket = aws_s3_bucket.lambda_deploy.id
  acl    = "private"
}

resource "aws_s3_object" "open_figi_cache_deploy" {
  bucket = aws_s3_bucket.lambda_deploy.id
  key    = data.archive_file.lambda.output_path
  source = data.archive_file.lambda.output_path
}

resource "aws_lambda_function" "open_figi_cache" {
  
  depends_on = [
    aws_s3_object.open_figi_cache_deploy
  ]
  
  function_name = "OpenFigiCache"

  # The bucket name as created earlier with "aws s3api create-bucket"
  s3_bucket = aws_s3_bucket.lambda_deploy.id
  s3_key    = data.archive_file.lambda.output_path

  # "main" is the filename within the zip file (main.js) and "handler"
  # is the name of the property under which the handler function was
  # exported in that file.
  handler = "main.lambda_handler"
  runtime = "python3.9"

  role = "${aws_iam_role.lambda_exec.arn}"

  environment {
    variables = {
      API_KEY = var.api_key
    }
  }
}

resource "aws_cloudwatch_log_group" "open_figi_cache" {
  name = "/aws/lambda/${aws_lambda_function.open_figi_cache.function_name}"

  retention_in_days = 7
}

#
# API Gateway Resources
#

#
# IAM Resources 
#

resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

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
  # TODO custom policy with elasticache read/write/delete permissions
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
