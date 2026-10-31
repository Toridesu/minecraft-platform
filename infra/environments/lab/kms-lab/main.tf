locals {
  name_prefix = "pmp-kms-lab"
  lab_roles   = var.enable_kms_lab ? toset(["allowed", "denied", "cleanup"]) : toset([])
}

data "aws_caller_identity" "lab" {
  count = var.enable_kms_lab ? 1 : 0
}

resource "aws_kms_key" "lab" {
  count = var.enable_kms_lab ? 1 : 0

  description              = "Disposable learning key; never use for state, World, SNS or backups."
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  multi_region             = false
  enable_key_rotation      = true
  deletion_window_in_days  = 7
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableAccountIAMDelegation"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.lab[0].account_id}:root" }
      Action    = "kms:*"
      Resource  = "*" # In a key policy, this refers to the attached key.
    }]
  })
}

resource "aws_kms_alias" "lab" {
  count = var.enable_kms_lab ? 1 : 0

  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.lab[0].key_id
}

resource "aws_iam_role" "lab" {
  for_each = local.lab_roles

  name = "${local.name_prefix}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.lab_assumer_arn }
      Action    = "sts:AssumeRole"
    }]
  })

  lifecycle {
    precondition {
      condition     = can(regex("^arn:aws:iam::${data.aws_caller_identity.lab[0].account_id}:(role|user)/.+$", var.lab_assumer_arn))
      error_message = "Choose an exact IAM role/user ARN in this account before enabling the lab."
    }
  }
}

resource "aws_iam_role_policy" "lab" {
  for_each = local.lab_roles

  name = "${local.name_prefix}-${each.key}"
  role = aws_iam_role.lab[each.key].id
  policy = each.key == "cleanup" ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:DescribeKey", "kms:CancelKeyDeletion"]
        Resource = aws_kms_key.lab[0].arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:ScheduleKeyDeletion"
        Resource = aws_kms_key.lab[0].arn
        Condition = {
          NumericEquals = { "kms:ScheduleKeyDeletionPendingWindowInDays" = 7 }
        }
      }
    ]
    }) : jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = "kms:DescribeKey"
        Resource = aws_kms_key.lab[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:Decrypt"]
        Resource = aws_kms_key.lab[0].arn
        Condition = {
          StringEquals = { "kms:EncryptionContext:Project" = var.project_name }
        }
      }
      ], each.key == "denied" ? [{
        Sid      = "DemonstrateExplicitDeny"
        Effect   = "Deny"
        Action   = "kms:Decrypt"
        Resource = aws_kms_key.lab[0].arn
    }] : [])
  })
}
