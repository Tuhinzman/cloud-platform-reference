provider "aws" {
  region = "us-east-1"

  allowed_account_ids = [var.allowed_account_id]

  default_tags {
    tags = {
      Project     = "cloud-platform-reference"
      Environment = "dev"
      Component   = "network"
      Lifecycle   = "ephemeral"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
    }
  }
}
