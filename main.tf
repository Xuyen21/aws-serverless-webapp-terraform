resource "random_id" "suffix" {
  byte_length = 4
}

# ---------- 1. S3 static website ----------
resource "aws_s3_bucket" "site" {
  bucket        = "${var.project_name}-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  depends_on = [aws_s3_bucket_public_access_block.site]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
    }]
  })
}

resource "aws_s3_bucket_cors_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  cors_rule {
    allowed_methods = ["GET", "POST"]
    allowed_origins = ["*"] # development only
    allowed_headers = ["*"]
  }
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/frontend/index.html.tpl", {
    api_url = "${aws_api_gateway_stage.main.invoke_url}/get_balance"
  })
  etag = md5(templatefile("${path.module}/frontend/index.html.tpl", {
    api_url = "${aws_api_gateway_stage.main.invoke_url}/get_balance"
  }))
}

# ---------- 2. DynamoDB ----------
resource "aws_dynamodb_table" "accounts" {
  name         = "accounts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "account_id"

  attribute {
    name = "account_id"
    type = "S"
  }
}

locals {
  sample_accounts = {
    "1001" = { balance = 2500, user_name = "Alice Smith", user_address = "12 Main St" }
    "1002" = { balance = 780, user_name = "Bob Jones", user_address = "34 Oak Ave" }
    "1003" = { balance = 15300, user_name = "Carol White", user_address = "56 Pine Rd" }
  }
}

resource "aws_dynamodb_table_item" "sample" {
  for_each   = local.sample_accounts
  table_name = aws_dynamodb_table.accounts.name
  hash_key   = aws_dynamodb_table.accounts.hash_key
  item = jsonencode({
    account_id   = { S = each.key }
    balance      = { N = tostring(each.value.balance) }
    user_name    = { S = each.value.user_name }
    user_address = { S = each.value.user_address }
  })
}

# ---------- 3. Lambda ----------
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_balance.py"
  output_path = "${path.module}/lambda/get_balance.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamo" {
  name = "dynamodb-read"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.accounts.arn
    }]
  })
}

resource "aws_lambda_function" "get_balance" {
  function_name    = "${var.project_name}-get-balance"
  role             = aws_iam_role.lambda.arn
  handler          = "get_balance.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.accounts.name
      CORS_ORIGIN = var.cors_allowed_origin
    }
  }
}

# ---------- 4. API Gateway ----------
resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project_name}-api"
}

resource "aws_api_gateway_resource" "get_balance" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "get_balance"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.get_balance.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.get_balance.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_balance.invoke_arn
}

# CORS preflight (OPTIONS)
resource "aws_api_gateway_method" "options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.get_balance.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_balance.id
  http_method = aws_api_gateway_method.options.http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_balance.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.get_balance.id
  http_method = aws_api_gateway_method.options.http_method
  status_code = aws_api_gateway_method_response.options.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allowed_origin}'"
  }
  depends_on = [aws_api_gateway_integration.options]
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_balance.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.get_balance.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.post.id,
      aws_api_gateway_method.options.id,
      aws_api_gateway_integration.options.id,
      aws_api_gateway_integration_response.options.id,
    ]))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_api_gateway_integration.post, aws_api_gateway_integration.options]
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.stage_name
}
