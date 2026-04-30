data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  nginx_conf = templatefile("${path.module}/templates/nginx-stream.conf.tftpl", {
    backends = var.backends
  })

  proxy_user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    nginx_conf = local.nginx_conf
  })
}

resource "aws_instance" "proxy" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.proxy_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.proxy.id]
  iam_instance_profile   = aws_iam_instance_profile.proxy.name

  user_data                   = local.proxy_user_data
  user_data_replace_on_change = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-proxy"
  })
}

resource "aws_lb_target_group_attachment" "proxy" {
  for_each = local.backends_by_name

  target_group_arn = aws_lb_target_group.backend[each.key].arn
  target_id        = aws_instance.proxy.private_ip
  port             = each.value.port
}
