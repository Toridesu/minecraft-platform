output "backup_bucket_name" {
  description = "Backup bucket name passed to backup/restore operations."
  value       = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  description = "Exact backup bucket ARN passed to the session-runtime IAM policy."
  value       = aws_s3_bucket.backup.arn
}
