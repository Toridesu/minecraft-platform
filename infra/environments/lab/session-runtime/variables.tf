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
