#GENERAL
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy the signals infraestructure."
}

variable "terraform_location" {
  type        = string
  default     = ""
  description = "Terraform project location to use on AWS tagging."
}

variable "project" {
  type        = string
  default     = "zaelot-signals"
  description = "Project name."
}

variable "environment" {
  type        = string
  default     = ""
  description = "Project environment (dev, test, stage, prod)."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID for Redshift and related components deployment."
}
#APIGATEWAY
variable "api_gateway_stage" {
  type        = string
  default     = ""
  description = "Api Gateway stage to use on deployment."
}

variable "api_gateway_stage_description" {
  type        = string
  default     = ""
  description = "Api Gateway stage description to use on deployment."
}
#APIGATEWAY USAGE PLAN
variable "quota_limit" {
  type        = number
  default     = "1000"
  description = "Number of requests a user can make to the API with the associated Api Key."
}

variable "quota_period" {
  type        = string
  default     = "MONTH"
  description = "Period of time in which the quota limit is going to be reset for the associated Api Key. (DAY, WEEK, MONTH)"
}

variable "throttling_rate_limit" {
  type        = number
  default     = "100"
  description = "Api Gateway Usage plan rate for adding tokens to the bucket. Average request/s over an extended period of time."
}

variable "throttling_burst_limit" {
  type        = number
  default     = "100"
  description = "Api Gateway Usage plan token bucket capacity."
}
#REDSHIFT CLUSTER
variable "database_name" {
  type        = string
  default     = ""
  description = "Redshift database name."
}

variable "master_password" {
  type        = string
  default     = ""
  description = "Redshift database master password."
}

variable "master_username" {
  type        = string
  default     = ""
  description = "Redshift database master username."
}

variable "node_type" {
  type        = string
  default     = ""
  description = "Redshift cluster node type."
}

variable "cluster_type" {
  type        = string
  default     = ""
  description = "Redshift cluster type."
}

variable "cluster_subnet_group_name" {
  type        = string
  default     = ""
  description = "Cluster Subnet Group Name.(Put only public subnets on the cluster subnet group)"
}
#KINESIS FIREHOSE
variable "aws_region_cidr_block" {
  type        = string
  default     = ""
  description = "Region cidr: :https://docs.aws.amazon.com/vpc/latest/userguide/aws-ip-ranges.html#aws-ip-download"
}

variable "firehose_data_table_name" {
  type        = string
  default     = "signals"
  description = " The name of the table in the redshift cluster that the s3 bucket will copy to."
}

variable "firehose_data_table_columns" {
  type        = string
  default     = ""
  description = "The data table columns that will be targeted by the copy command."
}

variable "firehose_copy_options" {
  type        = string
  default     = ""
  description = "Copy options for copying the data from the s3 intermediate bucket into redshift."
}

variable "redshift_retry_duration" {
  type        = string
  default     = ""
  description = "The length of time (seconds) during which Firehose retries delivery after a failure."
}

variable "redshift_data_statement" {
  type        = string
  default     = ""
  description = "SQL to execute on the redshift cluster."
}
