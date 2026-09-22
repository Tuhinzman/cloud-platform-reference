terraform {
  backend "s3" {
    key          = "dev-datastore/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
