output "state_bucket_name" {
  description = "Terraform state bucket name."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "Terraform state bucket ARN."
  value       = aws_s3_bucket.terraform_state.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "github_plan_role_arn" {
  description = "GitHub Actions Terraform plan role ARN."
  value       = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  description = "GitHub Actions Terraform apply role ARN."
  value       = aws_iam_role.github_apply.arn
}