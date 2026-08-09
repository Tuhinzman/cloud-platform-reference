terraform {
  # S3 native state locking reached general availability in Terraform 1.11.0,
  # which also deprecated the DynamoDB locking arguments. This root uses that
  # locking, so 1.11 is the floor. The upper bound keeps a future major release
  # from arriving without review.
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
