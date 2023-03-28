#Last no tainted infraestructure.

#General config
locals {
  region                        = var.region
  environment                   = var.environment
  project                       = var.project
  terraform_location            = var.terraform_location
  api_gateway_stage             = var.api_gateway_stage
  api_gateway_stage_description = var.api_gateway_stage_description
  quota_limit                   = var.quota_limit
  quota_period                  = var.quota_period
  throttling_burst_limit        = var.throttling_burst_limit
  throttling_rate_limit         = var.throttling_rate_limit
}

provider "aws" {
  region = local.region
}

#DataSources

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "apigateway_trust_policy_document" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "kinesis_putrecord_policy_document" {
  statement {
    effect    = "Allow"
    actions   = ["kinesis:PutRecord"]
    resources = ["${aws_kinesis_stream.signal_stream.arn}"]
  }
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.signal_api.id
  sensitive   = false
  description = "ApiGateway ID for signal"
  depends_on = [
    aws_api_gateway_rest_api.signal_api,
  ]
}

# Roles
# Create an IAM role for Kinesis Firehose to write to S3
resource "aws_iam_role" "firehose_role" {
  name = "firehose_role-${local.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

#  Kinesis putrecord role
resource "aws_iam_role" "kinesis_putrecord_role" {
  name               = "kinesis_putrecord_role-${local.environment}"
  description        = "kinesis_putrecord_role for apigateway"
  assume_role_policy = data.aws_iam_policy_document.apigateway_trust_policy_document.json
}

# Policies

#  Kinesis putrecord policy
resource "aws_iam_policy" "kinesis_put_record_policy" {
  name        = "kinesis_put_record_policy-${local.environment}"
  description = "kinesis_put_record_policy for signal_stream"
  policy      = data.aws_iam_policy_document.kinesis_putrecord_policy_document.json
}

# Policy attachments

# Grant the Kinesis Firehose role permission to write to S3
resource "aws_iam_role_policy_attachment" "firehose_s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.firehose_role.name
}

# Grant the Kinesis Firehose role permission to read from Kinesis Stream
resource "aws_iam_role_policy_attachment" "firehose_kinesis_stream_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess"
  role       = aws_iam_role.firehose_role.name
}

# Attach a policy to put records on kinesis to the kinesis_putrecord_role_for_apigateway role
resource "aws_iam_role_policy_attachment" "kinesis_putrecord_role_attachments" {
  policy_arn = aws_iam_policy.kinesis_put_record_policy.arn
  role       = aws_iam_role.kinesis_putrecord_role.name
}

#S3

#Create an S3 bucket
resource "aws_s3_bucket" "signal_bucket" {
  bucket = "signal-bucket-${local.environment}"

  tags = {
    Created_By  = data.aws_caller_identity.current.arn
    Project     = local.project
    Environment = local.environment
    CostCode    = local.project
    Terraform   = local.terraform_location
  }
}

#Kinesis Data Stream
resource "aws_kinesis_stream" "signal_stream" {
  name            = "signal-stream-${local.environment}"
  encryption_type = "NONE"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = {
    Created_By  = data.aws_caller_identity.current.arn
    Project     = local.project
    Environment = local.environment
    CostCode    = local.project
    Terraform   = local.terraform_location
  }
}

#ApiGateway REST API 
resource "aws_api_gateway_rest_api" "signal_api" {
  name = "signal_api-${local.environment}"
}

#ApiGateway
resource "aws_api_gateway_resource" "signals" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  parent_id   = aws_api_gateway_rest_api.signal_api.root_resource_id
  path_part   = "signals"
}


#Methods
#POST
resource "aws_api_gateway_method" "signal_post" {
  rest_api_id      = aws_api_gateway_rest_api.signal_api.id
  resource_id      = aws_api_gateway_resource.signals.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.header.x-api-key" = true
  }
}

#POST Response
resource "aws_api_gateway_method_response" "signal_post_200_response" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  resource_id = aws_api_gateway_resource.signals.id
  http_method = aws_api_gateway_method.signal_post.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

#POST Response Integration
resource "aws_api_gateway_integration_response" "signals_post_response_integration" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  resource_id = aws_api_gateway_resource.signals.id
  http_method = aws_api_gateway_method.signal_post.http_method
  status_code = aws_api_gateway_method_response.signal_post_200_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Api-Key'"
  }

  response_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200,
  "body": {
    "sequenceNumber": "$util.escapeJavaScript($input.path('$.SequenceNumber'))",
    "shardId": "$util.escapeJavaScript($input.path('$.ShardId'))",
  }
}
EOF
  }
  depends_on = [
    aws_api_gateway_integration.signals_kinesis,
    aws_api_gateway_method.signal_post,
  ]
}

resource "aws_api_gateway_integration" "signals_kinesis" {
  rest_api_id             = aws_api_gateway_rest_api.signal_api.id
  resource_id             = aws_api_gateway_resource.signals.id
  http_method             = aws_api_gateway_method.signal_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${local.region}:kinesis:action/PutRecord"
  credentials             = aws_iam_role.kinesis_putrecord_role.arn

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role.kinesis_putrecord_role
  ]
}

resource "aws_api_gateway_method_settings" "signals_post_settings" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  stage_name  = aws_api_gateway_stage.signals_stage.stage_name
  method_path = "${aws_api_gateway_resource.signals.path_part}/${aws_api_gateway_method.signal_post.http_method}"

  settings {
    logging_level                           = "INFO"
    metrics_enabled                         = true
    throttling_burst_limit                  = 5000
    throttling_rate_limit                   = 10000
    cache_data_encrypted                    = true
    cache_ttl_in_seconds                    = 300
    require_authorization_for_cache_control = false
  }
}

#STAGE AND DEPLOYMENT
resource "aws_api_gateway_deployment" "signals_deployment" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  triggers = {
    # NOTE: The configuration below will satisfy ordering considerations,
    #       but not pick up all future REST API changes. More advanced patterns
    #       are possible, such as using the filesha1() function against the
    #       Terraform configuration file(s) or removing the .id references to
    #       calculate a hash against whole resources. Be aware that using whole
    #       resources will show a difference after the initial implementation.
    #       It will stabilize to only change when resources change afterwards.
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.signals.id,
      aws_api_gateway_method.signal_post.id,
      aws_api_gateway_integration.signals_kinesis.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.signals_kinesis,
  ]
}

resource "aws_api_gateway_stage" "signals_stage" {
  deployment_id = aws_api_gateway_deployment.signals_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.signal_api.id
  stage_name    = local.api_gateway_stage
  description   = local.api_gateway_stage_description

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.signals_log_group.arn

    format = jsonencode({
      "requestId" : "$context.requestId",
      "ip" : "$context.identity.sourceIp",
      "requestTime" : "$context.requestTime",
      "httpMethod" : "$context.httpMethod",
      "resourcePath" : "$context.resourcePath",
      "status" : "$context.status",
      "protocol" : "$context.protocol",
      "responseLength" : "$context.responseLength"
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.signals_log_group,
  ]
}

#STAGE LOG ACCESS LOG GROUP
resource "aws_cloudwatch_log_group" "signals_log_group" {
  name = "/aws/api_gateway/${aws_api_gateway_rest_api.signal_api.name}"

  lifecycle {
    create_before_destroy = true
  }
}

#API KEY
resource "aws_api_gateway_api_key" "signals_api_key" {
  name    = "signals_api_key-${local.environment}"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "signals_usage_plan" {
  name = "signals_usage_plan-${local.environment}"

  quota_settings {
    limit  = local.quota_limit
    period = local.quota_period
  }

  throttle_settings {
    rate_limit  = local.throttling_rate_limit
    burst_limit = local.throttling_burst_limit
  }

  api_stages {
    api_id = aws_api_gateway_rest_api.signal_api.id
    stage  = aws_api_gateway_stage.signals_stage.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "signals_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.signals_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.signals_usage_plan.id
}