provider "aws" {
  region = "us-east-1"

  # Any account other than the dedicated project account is a hard stop, so the
  # provider verifies the caller's account before it does anything. A wrong
  # credential then fails at the first API call instead of creating this
  # project's first billable resource somewhere it does not belong.
  allowed_account_ids = [var.allowed_account_id]

  # The six mandatory tags of ADR-0013. Only the bucket is a taggable AWS
  # resource here, so these reach the bucket alone. The four configuration
  # resources below are sub-resources of it and carry no tags of their own.
  default_tags {
    tags = {
      Project     = "cloud-platform-reference"
      Environment = "shared"
      Component   = "terraform-state"
      Lifecycle   = "persistent"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # Refuse to delete state objects in order to complete a bucket destroy.
  force_destroy = false

  lifecycle {
    # Reject any plan that would destroy or replace this bucket. This is a
    # Terraform-side control only. It does not stop a console or CLI deletion.
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  # Object versions are the primary Terraform state recovery path, so no
  # noncurrent-version expiry is configured. Expiring them would trade recovery
  # history for a negligible saving on files this small.
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}
