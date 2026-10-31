locals {
  manage_instance_iam = var.existing_instance_profile_name == ""
  instance_profile    = local.manage_instance_iam ? aws_iam_instance_profile.minecraft[0].name : var.existing_instance_profile_name
}

data "aws_iam_policy_document" "minecraft_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "minecraft_instance" {
  count = local.manage_instance_iam ? 1 : 0

  name               = "${local.name_prefix}-minecraft-instance"
  assume_role_policy = data.aws_iam_policy_document.minecraft_assume_role.json

  tags = {
    Name = "${local.name_prefix}-minecraft-instance"
  }
}

resource "aws_iam_role_policy_attachment" "minecraft_ssm" {
  count = local.manage_instance_iam ? 1 : 0

  role       = aws_iam_role.minecraft_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "minecraft" {
  count = local.manage_instance_iam ? 1 : 0

  name = "${local.name_prefix}-minecraft-profile"
  role = aws_iam_role.minecraft_instance[0].name

  tags = {
    Name = "${local.name_prefix}-minecraft-profile"
  }
}

moved {
  from = aws_iam_role.minecraft_instance
  to   = aws_iam_role.minecraft_instance[0]
}

moved {
  from = aws_iam_role_policy_attachment.minecraft_ssm
  to   = aws_iam_role_policy_attachment.minecraft_ssm[0]
}

moved {
  from = aws_iam_instance_profile.minecraft
  to   = aws_iam_instance_profile.minecraft[0]
}
