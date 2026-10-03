data "aws_iam_policy_document" "minecraft_backup" {
  count = var.backup_bucket_arn == "" ? 0 : 1

  statement {
    sid       = "LocateBackupBucket"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation"]
    resources = [var.backup_bucket_arn]
  }

  statement {
    sid    = "ListBackups"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
    ]

    resources = [var.backup_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["backups/*"]
    }
  }

  statement {
    sid    = "ReadWriteBackups"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = ["${var.backup_bucket_arn}/backups/*"]
  }
}

resource "aws_iam_role_policy" "minecraft_backup" {
  count = var.backup_bucket_arn == "" ? 0 : 1

  name   = "${local.name_prefix}-minecraft-backup"
  role   = aws_iam_role.minecraft_instance.name
  policy = data.aws_iam_policy_document.minecraft_backup[0].json
}