variable "enable_kms_lab" {
  description = "Define the disposable KMS lab. Creating the key incurs charges."
  type        = bool
  default     = false
}

variable "aws_region" {
  type        = string
  description = "Region for the independent KMS exercise."
  default     = "ap-northeast-1"
}

variable "project_name" {
  type        = string
  description = "Project tag and non-secret encryption context value."
  default     = "minecraft-platform"
}

variable "owner" {
  type        = string
  description = "Owner of the disposable learning resources."
}

variable "run_id" {
  type        = string
  description = "Identifier for the learning session."
}

variable "expires_at" {
  type        = string
  description = "Reminder tag; it does not automatically delete the key."
}

variable "lab_assumer_arn" {
  type        = string
  description = "Exact IAM role/user ARN trusted to assume the lab roles; required when enabled."
  default     = ""
}
