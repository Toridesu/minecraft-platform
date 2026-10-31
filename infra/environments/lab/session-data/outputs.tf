output "backup_bucket_name" {
  description = "Backup bucket name passed to backup/restore operations."
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "Exact backup bucket ARN passed to the session-runtime IAM policy."
  value       = aws_s3_bucket.backup.arn
}

output "aws_backup_profile" {
  description = "Values for on-demand job requests; no backup is started by this output."
  value = var.enable_aws_backup_profile ? {
    vault_name       = aws_backup_vault.ebs_lab[0].name
    vault_arn        = aws_backup_vault.ebs_lab[0].arn
    service_role_arn = aws_iam_role.ebs_backup[0].arn
  } : null
}
