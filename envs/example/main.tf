terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

variable "aws_profile" {
  description = "AWS CLI profile (uses cached SSO credentials from `aws sso login`)."
  type        = string
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "name_prefix" {
  type    = string
  default = "tf-poc"
}

variable "azs" {
  type    = list(string)
  default = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "databricks_egress_cidrs" {
  description = "Databricks serverless egress CIDRs of the workspace that will reach this NLB. Refresh from https://www.databricks.com/networking/v1/ip-ranges.json (platform=aws, type=outbound)."
  type        = list(string)
  # us-west-2, fetched 2026-04-28
  default = [
    "18.246.106.0/24",
    "44.234.192.32/28",
    "3.42.138.0/25",
    "52.27.216.188/32",
  ]
}

module "egress" {
  source = "../../modules/serverless-egress-static-ip"

  name_prefix             = var.name_prefix
  azs                     = var.azs
  databricks_egress_cidrs = var.databricks_egress_cidrs
  backends = [
    {
      name          = "postgres"
      port          = 5432
      upstream_host = "ep-empty-voice-d12ttxav.database.us-west-2.cloud.databricks.com"
    },
  ]
}

output "nat_eip_public_ip" {
  description = "The static egress IP that external services should whitelist."
  value       = module.egress.nat_eip_public_ip
}

output "vpc_id" {
  value = module.egress.vpc_id
}

output "public_subnet_ids" {
  value = module.egress.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.egress.private_subnet_ids
}

output "nlb_dns_name" {
  value = module.egress.nlb_dns_name
}
