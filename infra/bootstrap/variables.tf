variable "aws_region" {
  description = "AWS region used by the bootstrap."
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name."
  type        = string
  default     = "minecraft-platform"
}

variable "state_bucket_prefix" {
  description = "Prefix for the Terraform state bucket name."
  type        = string
  default     = "pmp-terraform-state-"
}