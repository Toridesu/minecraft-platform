# Independent learning state; never encrypt this state with the disposable key.
# Local state files are excluded from Git. No remote state is accessed here.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
