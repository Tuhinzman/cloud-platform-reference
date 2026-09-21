terraform {
  # 1.11 floor: S3 native state locking and the write-only master password.
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
