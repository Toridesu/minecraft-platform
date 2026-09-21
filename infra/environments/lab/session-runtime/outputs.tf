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
