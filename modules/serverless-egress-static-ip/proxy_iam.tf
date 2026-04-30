data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "${var.name_prefix}-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-proxy-role"
  })
}

# SSM Session Manager: lets us `aws ssm start-session` into the proxy without
# opening SSH/22 or managing keypairs. Pulls the agent's required IAM perms.
resource "aws_iam_role_policy_attachment" "proxy_ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "proxy" {
  name = "${var.name_prefix}-proxy-profile"
  role = aws_iam_role.proxy.name

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-proxy-profile"
  })
}
