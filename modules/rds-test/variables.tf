variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "nat_eip_public_ip" {
  description = "Static egress IP of the NAT Gateway. RDS security group allows inbound 5432 from this IP only."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the RDS VPC."
  type        = string
  default     = "10.111.0.0/24"
}

variable "azs" {
  description = "Availability zones for the RDS subnet group (at least 2 required)."
  type        = list(string)
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "testdb"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "postgres"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "databricks_egress_cidrs" {
  description = "Databricks serverless egress CIDRs. Allows direct Serverless -> RDS connections without going through the NLB."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
