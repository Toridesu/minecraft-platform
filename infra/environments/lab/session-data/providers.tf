provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
      RunId       = var.run_id
      ExpiresAt   = var.expires_at
      DataClass   = "disposable"
    }
  }
}
