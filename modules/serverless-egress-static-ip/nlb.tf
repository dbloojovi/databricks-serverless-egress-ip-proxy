resource "aws_lb" "main" {
  name               = "${var.name_prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.nlb.id]

  enable_cross_zone_load_balancing = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-nlb"
  })
}

resource "aws_lb_target_group" "backend" {
  for_each = local.backends_by_name

  name        = "${var.name_prefix}-${each.key}-tg"
  port        = each.value.port
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-${each.key}-tg"
  })
}

resource "aws_lb_listener" "backend" {
  for_each = local.backends_by_name

  load_balancer_arn = aws_lb.main.arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend[each.key].arn
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-${each.key}-listener"
  })
}
