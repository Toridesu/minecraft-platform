terraform {
  required_version = "= 1.15.8"

  backend "s3" {
    bucket       = "pmp-terraform-state-77fff8da943327a1928073a768"
    key          = "pmp/lab/session-runtime/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}