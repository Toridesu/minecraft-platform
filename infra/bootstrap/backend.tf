terraform {
  backend "s3" {
    bucket       = "pmp-terraform-state-77fff8da943327a1928073a768"
    key          = "pmp/bootstrap/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}