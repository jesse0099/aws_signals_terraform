locals {
  #GENERAL
  region             = var.region
  environment        = var.environment
  project            = var.project
  vpc_id             = var.vpc_id
  terraform_location = var.terraform_location
  #APIGATEWAY
  api_gateway_stage             = var.api_gateway_stage
  api_gateway_stage_description = var.api_gateway_stage_description
  #USAGE PLAN
  quota_limit            = var.quota_limit
  quota_period           = var.quota_period
  throttling_burst_limit = var.throttling_burst_limit
  throttling_rate_limit  = var.throttling_rate_limit
  #REDSHIFT CLUSTER
  database_name             = var.database_name
  master_username           = var.master_username
  master_password           = var.master_password
  node_type                 = var.node_type
  cluster_type              = var.cluster_type
  cluster_subnet_group_name = var.cluster_subnet_group_name
  redshift_data_statement   = var.redshift_data_statement
  #KINESIS_FIREHOSE
  aws_region_cidr_block                = var.aws_region_cidr_block
  firehose_data_table_name             = var.firehose_data_table_name
  firehose_data_table_columns          = var.firehose_data_table_columns
  firehose_copy_options                = var.firehose_copy_options
  redshift_retry_duration              = var.redshift_retry_duration
  kinesis_s3_buffer_size               = var.kinesis_s3_buffer_size
  kinesis_backup_s3_buffer_size        = var.kinesis_backup_s3_buffer_size
  kinesis_s3_buffer_interval           = var.kinesis_s3_buffer_interval
  kinesis_backup_s3_buffer_interval    = var.kinesis_backup_s3_buffer_interval
  kinesis_backup_s3_compression_format = var.kinesis_backup_s3_compression_format
  kinesis_s3_compression_format        = var.kinesis_s3_compression_format
  api_gateway_key_required             = var.api_gateway_key_required
  #SIGNALS PROJECT EXTERNAL RESOURCES
  signals_backend_machine_public_ip = var.signals_backend_machine_public_ip
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      CostCode    = local.project
      Terraform   = local.terraform_location
    }
  }
}

#DataSources
data "aws_redshift_subnet_group" "percy_subnet_group" {
  name = local.cluster_subnet_group_name
}

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

data "aws_iam_policy_document" "firehose_s3_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "s3:*",
      "s3-object-lambda:*"
    ]
    resources = [
      "${aws_s3_bucket.signal_bucket.arn}",
      "${aws_s3_bucket.signal_bucket.arn}/*"
    ]
  }
}

data "aws_iam_policy" "s3_read_only_access" {
  name = "AmazonS3ReadOnlyAccess"
}

data "aws_iam_policy" "kinesis_read_only_access" {
  name = "AmazonKinesisReadOnlyAccess"
}

data "aws_iam_policy" "redshift_all_commands_full_access" {
  name = "AmazonRedshiftAllCommandsFullAccess"
}

# Roles
# Redshift Cluster Role
resource "aws_iam_role" "signal_redshift_role" {
  name = "${local.project}-redshift_cluster-${local.environment}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service : [
            "redshift-serverless.amazonaws.com",
            "redshift.amazonaws.com",
            "sagemaker.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "firehose_role" {
  name = "${local.project}-firehose-${local.environment}-role"

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

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }
}

#  Kinesis putrecord role
resource "aws_iam_role" "kinesis_putrecord_role" {
  name               = "${local.project}-kinesis_putrecord-${local.environment}-role"
  description        = "kinesis_putrecord_role for apigateway"
  assume_role_policy = data.aws_iam_policy_document.apigateway_trust_policy_document.json

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }
}

# Policies

#  Kinesis putrecord policy
resource "aws_iam_policy" "kinesis_put_record_policy" {
  name        = "${local.project}-kinesis_put_record-${local.environment}-policy"
  description = "kinesis_put_record_policy for signal_stream"
  policy      = data.aws_iam_policy_document.kinesis_putrecord_policy_document.json

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }
}

resource "aws_iam_policy" "firehose_s3_policy" {
  name        = "${local.project}-firehose_s3_policy-${local.environment}-policy"
  description = "firehose s3 full management policy for ${local.project}"
  policy      = data.aws_iam_policy_document.firehose_s3_policy_document.json

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }
}

# Policy attachments

# Grant the Kinesis Firehose role permission to write to S3
resource "aws_iam_role_policy_attachment" "signal_firehose_s3_full_access_policy" {
  policy_arn = aws_iam_policy.firehose_s3_policy.arn
  role       = aws_iam_role.firehose_role.name
}

# Grant the Kinesis Firehose role permission to read from Kinesis Stream
resource "aws_iam_role_policy_attachment" "firehose_kinesis_stream_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess"
  role       = aws_iam_role.firehose_role.name
}

resource "aws_iam_role_policy_attachment" "kinesis_putrecord_role_policy" {
  policy_arn = aws_iam_policy.kinesis_put_record_policy.arn
  role       = aws_iam_role.kinesis_putrecord_role.name
}

resource "aws_iam_role_policy_attachment" "signal_redshift_s3_read_only_policy" {
  policy_arn = data.aws_iam_policy.s3_read_only_access.arn
  role       = aws_iam_role.signal_redshift_role.name
}

resource "aws_iam_role_policy_attachment" "signal_redshift_kinesis_read_only_policy" {
  policy_arn = data.aws_iam_policy.kinesis_read_only_access.arn
  role       = aws_iam_role.signal_redshift_role.name
}

resource "aws_iam_role_policy_attachment" "signal_redshift_all_commands_full_access_policy" {
  policy_arn = data.aws_iam_policy.redshift_all_commands_full_access.arn
  role       = aws_iam_role.signal_redshift_role.name
}

#SECURITY GROUPS
resource "aws_security_group" "signal_firehose_ingress" {
  name        = "${local.project}-firehose_to_redshift_ingress-${local.environment}-sg"
  description = "Firehose ingress access to Redshift cluster."
  vpc_id      = local.vpc_id

  ingress = [
    {
      cidr_blocks = [
        "3.239.196.201/32",
      ]
      description      = "Primary VPC exit node"
      from_port        = 5439
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5439
    },
    {
      cidr_blocks      = [local.aws_region_cidr_block]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    },
    {
      cidr_blocks = [
        local.signals_backend_machine_public_ip,
      ]
      description      = "Signals Backend Machine"
      from_port        = 5439
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5439
    }
  ]

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Created_By = data.aws_caller_identity.current.arn
  }

  lifecycle {
    create_before_destroy = true
  }
}

#S3

#Create an S3 bucket
resource "aws_s3_bucket" "signal_bucket" {
  bucket = "${local.project}-data-${local.environment}-s3"
  tags = {
    Created_By = data.aws_caller_identity.current.arn
  }
}

#KINESIS DATA STREAM
resource "aws_kinesis_stream" "signal_stream" {
  name            = "${local.project}-stream-${local.environment}"
  encryption_type = "NONE"
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = {
    Created_By = data.aws_caller_identity.current.arn
  }
}

#KINESIS DELIVERY STREAM


#REDSHIFT CLUSTER
resource "aws_redshift_cluster" "signals_redshift_cluster" {
  cluster_identifier        = "${local.project}-cluster-${local.environment}"
  database_name             = local.database_name
  master_username           = local.master_username
  master_password           = local.master_password
  node_type                 = local.node_type
  cluster_type              = local.cluster_type
  cluster_subnet_group_name = data.aws_redshift_subnet_group.percy_subnet_group.name

  vpc_security_group_ids = [
    aws_security_group.signal_firehose_ingress.id
  ]

  tags = {
    Created_By = data.aws_caller_identity.current.arn
  }
}

resource "aws_redshift_cluster_iam_roles" "signals_redshift_cluster_iam_roles" {
  cluster_identifier   = aws_redshift_cluster.signals_redshift_cluster.cluster_identifier
  iam_role_arns        = [aws_iam_role.signal_redshift_role.arn]
  default_iam_role_arn = aws_iam_role.signal_redshift_role.arn
}

resource "aws_redshiftdata_statement" "signals_redshift_data_statement" {
  cluster_identifier = aws_redshift_cluster.signals_redshift_cluster.cluster_identifier
  database           = aws_redshift_cluster.signals_redshift_cluster.database_name
  db_user            = aws_redshift_cluster.signals_redshift_cluster.master_username
  sql                = local.redshift_data_statement

  depends_on = [
    aws_redshift_cluster.signals_redshift_cluster
  ]
}

#KINESIS FIREHOSE
resource "aws_kinesis_firehose_delivery_stream" "signal_firehose" {
  name        = "${local.project}-firehose-${local.environment}"
  destination = "redshift"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.signal_stream.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }

  s3_configuration {
    role_arn        = aws_iam_role.firehose_role.arn
    bucket_arn      = aws_s3_bucket.signal_bucket.arn
    prefix          = "${local.project}-inputs-${local.environment}-"
    buffer_size     = local.kinesis_s3_buffer_size
    buffer_interval = local.kinesis_s3_buffer_interval
    compression_format = local.kinesis_s3_compression_format
  }

  redshift_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    cluster_jdbcurl    = "jdbc:redshift://${aws_redshift_cluster.signals_redshift_cluster.endpoint}/${aws_redshift_cluster.signals_redshift_cluster.database_name}"
    username           = local.master_username
    password           = local.master_password
    data_table_name    = local.firehose_data_table_name
    copy_options       = local.firehose_copy_options
    data_table_columns = local.firehose_data_table_columns
    s3_backup_mode     = "Enabled"
    retry_duration     = local.redshift_retry_duration

    s3_backup_configuration {
      role_arn        = aws_iam_role.firehose_role.arn
      bucket_arn      = aws_s3_bucket.signal_bucket.arn
      buffer_size     = local.kinesis_backup_s3_buffer_size
      buffer_interval = local.kinesis_backup_s3_buffer_interval
      prefix          = "${local.project}-backups-${local.environment}-"
      compression_format = local.kinesis_backup_s3_compression_format
    }
  }

  tags = {
    Created_By = data.aws_caller_identity.current.arn
  }
}

#ApiGateway REST API 
resource "aws_api_gateway_rest_api" "signal_api" {
  name = "${local.project}-${local.environment}"
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
  api_key_required = local.api_gateway_key_required

  request_parameters = {
    "method.request.header.x-api-key" = true
  }

  lifecycle {
    create_before_destroy = true
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

#STAGE ACCESS LOG GROUP
resource "aws_cloudwatch_log_group" "signals_log_group" {
  name = "/aws/api_gateway/${aws_api_gateway_rest_api.signal_api.name}"

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }

  lifecycle {
    create_before_destroy = true
  }
}

#API KEY
resource "aws_api_gateway_api_key" "signals_api_key" {
  name    = "${local.project}-api_key-${local.environment}"
  enabled = true

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }
}

resource "aws_api_gateway_usage_plan" "signals_usage_plan" {
  name = "${local.project}-usage_plan-${local.environment}"

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

  tags = {
    Created_By : data.aws_caller_identity.current.arn
  }
}

resource "aws_api_gateway_usage_plan_key" "signals_usage_plan_key" {
  key_id        = aws_api_gateway_api_key.signals_api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.signals_usage_plan.id
}