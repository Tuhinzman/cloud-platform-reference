terraform {
  # Partial configuration. The state bucket name is globally unique and belongs
  # to whoever runs this, so it arrives through -backend-config=backend.hcl and
  # is never committed. Everything a reviewer needs in order to judge the
  # backend stays here, in the repository.
  #
  # use_lockfile is S3 native state locking, generally available since Terraform
  # 1.11.0, which the required_version floor in versions.tf enforces. No
  # dynamodb_table is declared: it is the deprecated locking path and would add
  # a second resource to create, pay for, and decommission.
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
