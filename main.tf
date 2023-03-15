locals {
  region = var.region
}

provider "aws" {
    region = local.region
}