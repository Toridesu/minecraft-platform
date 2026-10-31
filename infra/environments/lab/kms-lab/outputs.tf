output "kms_lab" {
  description = "Key and role identities for the local request examples; no cryptographic operation is run."
  value = var.enable_kms_lab ? {
    key_arn            = aws_kms_key.lab[0].arn
    alias_name         = aws_kms_alias.lab[0].name
    role_arns          = { for name, role in aws_iam_role.lab : name => role.arn }
    encryption_context = { Project = var.project_name }
    deletion_days      = 7
  } : null
}
