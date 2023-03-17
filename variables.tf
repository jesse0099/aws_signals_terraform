variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy the signals infraestructure"
}

variable stage {
  type        = string
  default     = "signals_dev_01"
  description = <<EOT
    ApiGateway stage. 
    The same name is used to create a CloudWatch log group
  EOT
}

