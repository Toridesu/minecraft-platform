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

variable "allowed_client_cidr" {
  description = "IPv4 /32 allowed to connect to Minecraft. Empty means no inbound rule."
  type        = string
  default     = ""

  validation {
    condition = var.allowed_client_cidr == "" || (
      can(cidrnetmask(var.allowed_client_cidr)) &&
      can(regex("/32$", var.allowed_client_cidr))
    )
    error_message = "allowed_client_cidr must be empty or a valid IPv4 /32 CIDR."
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
  description = "Expiration value from the private input ledger."
  type        = string
}

variable "ubuntu_ami_id" {
  description = "Pinned Canonical Ubuntu Server 24.04 LTS x86_64 AMI for ap-northeast-1."
  type        = string
  default     = "ami-0722c84b91d123e55"
}