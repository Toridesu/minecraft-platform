# Optional, on-demand EBS lab. The vault/role outlive session-runtime.
# A vault alone does not start backups; request examples are generated locally.
resource "aws_backup_vault" "ebs_lab" {
  count = var.enable_aws_backup_profile ? 1 : 0

  name          = "${local.name_prefix}-ebs-lab"
  force_destroy = false

  # Use the service's default encryption, without a new customer-managed key.
  # EBS recovery points inherit source-volume encryption, not the vault key.
  tags = {
    Name = "${local.name_prefix}-ebs-lab"
  }
}

resource "aws_iam_role" "ebs_backup" {
  count = var.enable_aws_backup_profile ? 1 : 0

  name_prefix = "${local.name_prefix}-ebs-backup-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })
}

# AWS-maintained service policies keep the learning profile small. These cover
# more than this one EBS volume; they are not an EBS-only least-privilege policy.
resource "aws_iam_role_policy_attachment" "ebs_backup" {
  for_each = var.enable_aws_backup_profile ? toset([
    "AWSBackupServiceRolePolicyForBackup",
    "AWSBackupServiceRolePolicyForRestores",
  ]) : toset([])

  role       = aws_iam_role.ebs_backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/${each.value}"
}
