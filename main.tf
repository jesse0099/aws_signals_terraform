#General config
locals {
  region = var.region
  stage = var.stage
}

provider "aws" {
  region = local.region
}

# Create an IAM role for Kinesis Firehose to write to S3
resource "aws_iam_role" "firehose_role" {
  name = "example_firehose_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

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


#Kinesis Data Stream
resource "aws_kinesis_stream" "signal_stream" {
  name = "signal_stream"

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}

#Kinesis Firehose 
resource "aws_kinesis_firehose_delivery_stream" "signal_firehose"{
  name  = "signal_firehose"

  destination = "s3"

  s3_configuration {
    role_arn = aws_iam_role.firehose_role.arn
    bucket_arn = "arn:aws:s3:::devops-csv-resources-reports-dev"
    prefix = "signal_stream_test/"
  }

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.signal_stream.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }
}

#Policy documents
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

#  Kinesis putrecord role
resource "aws_iam_role" "kinesis_putrecord_role" {
  name = "kinesis_putrecord_role"
  description = "kinesis_putrecord_role for apigateway"
  assume_role_policy = data.aws_iam_policy_document.apigateway_trust_policy_document.json 
}

#  Kinesis putrecord policy
resource "aws_iam_policy" "kinesis_put_record_policy" {
  name        = "kinesis_put_record_policy"
  description = "kinesis_put_record_policy for signal_stream"
  policy      = data.aws_iam_policy_document.kinesis_putrecord_policy_document.json
}

# Attach a policy to put records on kinesis to the kinesis_putrecord_role_for_apigateway role
resource "aws_iam_role_policy_attachment" "kinesis_putrecord_role_attachments" {
  policy_arn = aws_iam_policy.kinesis_put_record_policy.arn  
  role = aws_iam_role.kinesis_putrecord_role.name
}

#ApiGateway REST API 
resource "aws_api_gateway_rest_api" "signal_api" {
  name = "signal_api"
}

#ApiGateway
resource "aws_api_gateway_resource" "signals" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  parent_id   = aws_api_gateway_rest_api.signal_api.root_resource_id
  path_part   = "signals"
}

resource "aws_api_gateway_method" "signal_post" {
  rest_api_id   = aws_api_gateway_rest_api.signal_api.id
  resource_id   = aws_api_gateway_resource.signals.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integrate the API Gateway REST API with the Kinesis Data Stream
resource "aws_api_gateway_integration" "signals_kinesis" {
  rest_api_id             = aws_api_gateway_rest_api.signal_api.id
  resource_id             = aws_api_gateway_resource.signals.id
  http_method             = aws_api_gateway_method.signal_post.http_method
  integration_http_method = "POST"
  type                  = "AWS"
  uri  = "arn:aws:apigateway:${local.region}:kinesis:action/PutRecord"

  request_parameters = {
    "integration.request.header.X-Amz-Target" = "'Kinesis_20131202.PutRecord'"
    "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
  }

  request_templates = {
    "application/json" = jsonencode({
      "StreamName" : "${aws_kinesis_stream.signal_stream.name}",
      "Data" : "$util.base64Encode($input.json('$.Data'))",
      "PartitionKey" : "$input.path('$.PartitionKey')"
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  credentials = aws_iam_role.kinesis_putrecord_role.arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  resource_id = aws_api_gateway_resource.signals.id
  http_method = aws_api_gateway_method.signal_post.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "signals_kinesis_default_response" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  resource_id = aws_api_gateway_resource.signals.id
  http_method = aws_api_gateway_method.signal_post.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

response_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200,
  "body": {
    "sequenceNumber": "$util.escapeJavaScript($input.path('$.SequenceNumber'))"
  }
}
EOF
  }

  depends_on = [
    aws_api_gateway_integration.signals_kinesis,
  ]
}

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
  stage_name    = "signals_dev_01"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.signals_log_group.arn
    
    format = jsonencode({
      "requestId": "$context.requestId",
      "ip": "$context.identity.sourceIp",
      "requestTime": "$context.requestTime",
      "httpMethod": "$context.httpMethod",
      "resourcePath": "$context.resourcePath",
      "status": "$context.status",
      "protocol": "$context.protocol",
      "responseLength": "$context.responseLength"
    })
  }

  depends_on = [
    aws_cloudwatch_log_group.signals_log_group,
  ]
}

resource "aws_cloudwatch_log_group" "signals_log_group"{
  name = "api-gateway/${local.stage}"
}

resource "aws_api_gateway_method_settings" "signals_settings" {
  rest_api_id = aws_api_gateway_rest_api.signal_api.id
  stage_name  = aws_api_gateway_stage.signals_stage.stage_name
  method_path = "${aws_api_gateway_resource.signals.path_part}/${aws_api_gateway_method.signal_post.http_method}"
  
  settings {
    logging_level = "INFO"
    metrics_enabled = true
    throttling_burst_limit = 5000
    throttling_rate_limit = 10000
    cache_data_encrypted = true
    cache_ttl_in_seconds = 300
    require_authorization_for_cache_control = false
  }
}