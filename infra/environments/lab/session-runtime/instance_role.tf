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
  name               = "${local.name_prefix}-minecraft-instance"
  assume_role_policy = data.aws_iam_policy_document.minecraft_assume_role.json

  tags = {
    Name = "${local.name_prefix}-minecraft-instance"
  }
}

resource "aws_iam_role_policy_attachment" "minecraft_ssm" {
  role       = aws_iam_role.minecraft_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "minecraft" {
  name = "${local.name_prefix}-minecraft-profile"
  role = aws_iam_role.minecraft_instance.name

  tags = {
    Name = "${local.name_prefix}-minecraft-profile"
  }
}