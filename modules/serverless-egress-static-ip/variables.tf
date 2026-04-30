variable "name_prefix" {
  description = "Prefix for all resource names. e.g. \"tf-poc\" produces \"tf-poc-vpc\", \"tf-poc-public-a\"."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /24 is plenty for this architecture (NLB + NAT + 1-2 proxies)."
  type        = string
  default     = "10.110.0.0/24"
}

variable "azs" {
  description = "Availability zones to use. At least 2 required for NLB high availability."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least 2 availability zones are required."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ. Hosts the NLB ENIs and the NAT Gateway. /27 = 32 IPs (27 usable) is AWS's recommended minimum for LB subnets."
  type        = list(string)
  default     = ["10.110.0.0/27", "10.110.0.32/27"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ. Hosts the NGINX proxy."
  type        = list(string)
  default     = ["10.110.0.64/27", "10.110.0.96/27"]
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "databricks_egress_cidrs" {
  description = "CIDRs to seed the Managed Prefix List with. After first apply, Terraform stops managing entries (lifecycle ignore_changes). Get current values from https://www.databricks.com/networking/v1/ip-ranges.json filtered by platform=aws, type=outbound, and your region."
  type        = list(string)
}

variable "prefix_list_max_entries" {
  description = "Max CIDR entries the prefix list can hold. Must be >= len(databricks_egress_cidrs). Each SG rule referencing this PL counts max_entries against the SG rule quota."
  type        = number
  default     = 10
}

variable "backends" {
  description = "Services exposed through the proxy. Each backend creates one NLB listener, target group, SG rules, and an NGINX stream upstream that proxies `port` to `upstream_host:upstream_port`. Set upstream_port to override `port` (e.g., listener 5432 -> upstream 5432 is the default)."
  type = list(object({
    name          = string
    port          = number
    upstream_host = string
    upstream_port = optional(number)
  }))
}

variable "proxy_instance_type" {
  description = "EC2 instance type for the NGINX proxy. t4g.nano is plenty for TCP relay."
  type        = string
  default     = "t4g.nano"
}
