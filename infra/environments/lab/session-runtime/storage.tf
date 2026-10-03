data "aws_kms_alias" "ebs" {
  name = "alias/aws/ebs"
}

resource "aws_ebs_volume" "minecraft_data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = 16
  type              = "gp3"
  encrypted         = true
  kms_key_id        = data.aws_kms_alias.ebs.target_key_arn

  tags = {
    Name = "${local.name_prefix}-minecraft-data"
  }
}

resource "aws_volume_attachment" "minecraft_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.minecraft_data.id
  instance_id = aws_instance.minecraft.id
}