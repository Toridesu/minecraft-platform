variable "aws_region" {
  description = "AWS region used by this learning lab."
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "minecraft-platform"
}

variable "environment" {
  description = "Logical environment name."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  description = "Resource owner tag value from the private input ledger."
  type        = string
}

variable "run_id" {
  description = "Unique identifier for this lab run."
  type        = string
}

variable "expires_at" {
  description = "Expiration tag; cleanup must be performed explicitly."
  type        = string
}

variable "enable_aws_backup_profile" {
  description = "Define the optional on-demand AWS Backup lab vault and service role."
  type        = bool
  default     = false
}

variable "backup_bucket_name" {
  description = "Optional deterministic CI bucket; empty preserves the manual-lab prefix."
  type        = string
  default     = ""
}
