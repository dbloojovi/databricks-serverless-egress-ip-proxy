output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.main.id
}

output "nat_eip_allocation_id" {
  value = aws_eip.nat.id
}

output "nat_eip_public_ip" {
  description = "The static egress IP. External services should whitelist this."
  value       = aws_eip.nat.public_ip
}

output "prefix_list_id" {
  description = "Managed Prefix List ID for Databricks serverless egress CIDRs. Rotation Lambda updates entries."
  value       = aws_ec2_managed_prefix_list.databricks_egress.id
}

output "nlb_security_group_id" {
  value = aws_security_group.nlb.id
}

output "proxy_security_group_id" {
  value = aws_security_group.proxy.id
}

output "nlb_arn" {
  value = aws_lb.main.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB. This is what Databricks serverless connects to (one DNS name, multiple listener ports)."
  value       = aws_lb.main.dns_name
}

output "target_group_arns" {
  description = "Target group ARN per backend, keyed by backend name. Step 4 attaches the proxy ENI as a target."
  value       = { for k, tg in aws_lb_target_group.backend : k => tg.arn }
}

output "proxy_instance_id" {
  value = aws_instance.proxy.id
}

output "proxy_private_ip" {
  value = aws_instance.proxy.private_ip
}
