resource "aws_instance" "minecraft" {
  ami                         = var.ubuntu_ami_id
  instance_type               = "m7i.large"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  iam_instance_profile        = local.instance_profile
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 16
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name        = "${local.name_prefix}-minecraft-root"
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      RunId       = var.run_id
      DataClass   = "disposable"
    }
  }

  tags = {
    Name = "${local.name_prefix}-minecraft"
  }
}
