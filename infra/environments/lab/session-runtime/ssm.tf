resource "aws_ssm_document" "minecraft_backup" {
  count = var.backup_bucket_arn != "" ? 1 : 0

  name            = "${local.name_prefix}-minecraft-backup"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/minecraft-backup-document.json")
}

resource "aws_ssm_document" "minecraft_restore" {
  count = var.backup_bucket_arn != "" ? 1 : 0

  name            = "${local.name_prefix}-minecraft-restore"
  document_type   = "Command"
  document_format = "JSON"
  content         = file("${path.module}/minecraft-restore-document.json")
}
