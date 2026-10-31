output "project_name" {
  description = "Configured project name."
  value       = var.project_name
}

output "environment" {
  description = "Configured logical environment."
  value       = var.environment
}

output "name_prefix" {
  description = "Resource name prefix for this environment."
  value       = local.name_prefix
}

output "world_volume" {
  description = "World EBS identity and AZ for the optional AWS Backup exercise."
  value = {
    id                = aws_ebs_volume.minecraft_data.id
    arn               = aws_ebs_volume.minecraft_data.arn
    availability_zone = aws_ebs_volume.minecraft_data.availability_zone
  }
}

output "backup_document" {
  description = "Fixed backup document name and version; pin this version when invoking."
  value = var.backup_bucket_arn != "" ? {
    name    = aws_ssm_document.minecraft_backup[0].name
    version = aws_ssm_document.minecraft_backup[0].latest_version
  } : null
}

output "restore_document" {
  description = "Fixed restore document name and version; pin this version when invoking."
  value = var.backup_bucket_arn != "" ? {
    name    = aws_ssm_document.minecraft_restore[0].name
    version = aws_ssm_document.minecraft_restore[0].latest_version
  } : null
}

output "ci_runtime" {
  value = {
    instance_id = aws_instance.minecraft.id
    volume_id   = aws_ebs_volume.minecraft_data.id
    vpc_id      = aws_vpc.lab.id
  }
}
