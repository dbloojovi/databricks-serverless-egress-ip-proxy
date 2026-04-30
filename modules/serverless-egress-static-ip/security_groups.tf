locals {
  # Map keyed by backend name so for_each is stable across plans.
  backends_by_name = { for b in var.backends : b.name => b }
}

resource "aws_security_group" "nlb" {
  name        = "${var.name_prefix}-nlb-sg"
  description = "NLB ENIs: ingress from Databricks serverless prefix list + intra-VPC health checks."
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nlb-sg"
  })
}

resource "aws_security_group" "proxy" {
  name        = "${var.name_prefix}-proxy-sg"
  description = "NGINX proxy: ingress from NLB ENIs (intra-VPC) only."
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-proxy-sg"
  })
}

# NLB ingress: Databricks serverless CIDRs (managed by prefix list) per backend port.
resource "aws_vpc_security_group_ingress_rule" "nlb_from_databricks" {
  for_each = local.backends_by_name

  security_group_id = aws_security_group.nlb.id
  prefix_list_id    = aws_ec2_managed_prefix_list.databricks_egress.id
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "Databricks serverless toNLB :${each.value.port} (${each.key})"
}

# NLB ingress: intra-VPC for NLB health checks against proxy targets.
# NLB health checks originate from within the VPC; allow VPC CIDR per backend port.
resource "aws_vpc_security_group_ingress_rule" "nlb_from_vpc" {
  for_each = local.backends_by_name

  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "VPC toNLB :${each.value.port} (${each.key}) for health checks"
}

resource "aws_vpc_security_group_egress_rule" "nlb_all" {
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All egress (NLB targets are intra-VPC, this is permissive default)"
}

# Proxy ingress: NLB target SG must allow traffic from the VPC CIDR (NLB preserves
# client IP by default; without preserve_client_ip it shows up as the NLB ENI IP,
# which is in VPC CIDR either way).
resource "aws_vpc_security_group_ingress_rule" "proxy_from_vpc" {
  for_each = local.backends_by_name

  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = "VPC toproxy :${each.value.port} (${each.key})"
}

resource "aws_vpc_security_group_egress_rule" "proxy_all" {
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All egress (proxy reaches backends + apt + SSM via NAT)"
}
