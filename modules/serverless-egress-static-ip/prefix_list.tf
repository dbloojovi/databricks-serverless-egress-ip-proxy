resource "aws_ec2_managed_prefix_list" "databricks_egress" {
  name           = "${var.name_prefix}-databricks-egress"
  address_family = "IPv4"
  max_entries    = var.prefix_list_max_entries

  dynamic "entry" {
    for_each = var.databricks_egress_cidrs
    content {
      cidr        = entry.value
      description = "databricks-serverless-egress"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-databricks-egress"
  })

  # After first apply, hand off entry management to the rotation Lambda.
  # Without this, every `terraform apply` would revert Lambda's updates.
  lifecycle {
    ignore_changes = [entry]
  }
}
