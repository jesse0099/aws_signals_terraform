variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy the signals infraestructure."
}

variable "project" {
  type        = string
  default     = "zaelot_signals"
  description = "Project name."
}

variable "environment" {
  type        = string
  default     = ""
  description = "Project environment (dev, test, stage, prod)."
}

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

variable "quota_limit" {
  type        = number
  default     = "1000"
  description = "Number of requests a user can make to the API."
}

variable "quota_period" {
  type        = string
  default     = "MONTH"
  description = "Period of time in which the quota limit is going to be reset. (DAY, WEEK, MONTH)"
}

variable "terraform_location" {
  type        = string
  default     = ""
  description = "Terraform project location to use on AWS tagging."
}
