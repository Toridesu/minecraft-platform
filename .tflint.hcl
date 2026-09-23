tflint {
  required_version = "= 0.64.0"
}

config {
  format            = "compact"
  call_module_type  = "local"
  force             = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}