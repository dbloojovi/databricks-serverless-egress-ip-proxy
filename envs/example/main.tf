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

variable "backends" {
  description = "External services to expose through the static egress IP. Each entry creates one NLB listener + target group + NGINX upstream. Set `upstream_port` only if it differs from `port` (default same)."
  type = list(object({
    name          = string
    port          = number
    upstream_host = string
    upstream_port = optional(number)
  }))
  default = []
}

variable "enable_rds_test" {
  description = "Deploy a self-contained RDS PostgreSQL instance and wire it as a backend on NLB port 5433. Use this to validate the static egress IP works end-to-end. Disable once validated."
  type        = bool
  default     = true
}

locals {
  rds_test_backend = var.enable_rds_test ? [{
    name          = "rds-test"
    port          = 5433
    upstream_host = module.rds[0].endpoint
    upstream_port = 5432
  }] : []
}

module "egress" {
  source = "../../modules/serverless-egress-static-ip"

  name_prefix             = var.name_prefix
  azs                     = var.azs
  databricks_egress_cidrs = var.databricks_egress_cidrs
  backends                = concat(var.backends, local.rds_test_backend)
}

module "rds" {
  count  = var.enable_rds_test ? 1 : 0
  source = "../../modules/rds-test"

  name_prefix             = var.name_prefix
  azs                     = var.azs
  nat_eip_public_ip       = module.egress.nat_eip_public_ip
  databricks_egress_cidrs = var.databricks_egress_cidrs
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

output "rds_endpoint" {
  description = "RDS hostname (connect via NLB port 5433). Null if enable_rds_test = false."
  value       = var.enable_rds_test ? module.rds[0].endpoint : null
}

output "rds_username" {
  value = var.enable_rds_test ? module.rds[0].username : null
}

output "rds_password" {
  value     = var.enable_rds_test ? module.rds[0].password : null
  sensitive = true
}
