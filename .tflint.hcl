tflint {
  required_version = "= 0.65.0"
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
