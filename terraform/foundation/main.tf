provider "aws" {
  region = "us-east-1"

  # Any account other than the dedicated project account is a hard stop, so the
  # provider verifies the caller's account before it does anything. A wrong
  # credential then fails at the first API call instead of creating a project
  # foundation somewhere it does not belong.
  allowed_account_ids = [var.allowed_account_id]

  # The six mandatory tags of ADR-0013. Only the bucket is a taggable AWS
  # resource here, so these reach the bucket alone. The four configuration
  # resources below are sub-resources of it and carry no tags of their own.
  #
  # Environment is "shared" because this is a persistent shared foundation and
  # belongs to none of the three environment roles. It is the same value the
  # state backend carries. Two foundations under different values would break
  # the cost attribution REQ-019 requires, because orphan scans and cost
  # grouping read this tag.
  default_tags {
    tags = {
      Project     = "cloud-platform-reference"
      Environment = "shared"
      Component   = "evidence-store"
      Lifecycle   = "persistent"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
    }
  }
}

resource "aws_s3_bucket" "evidence" {
  bucket = var.evidence_bucket_name

  # Refuse to delete stored evidence in order to complete a bucket destroy.
  force_destroy = false

  lifecycle {
    # Reject any plan that would destroy or replace this bucket. This is a
    # Terraform-side control only. It does not stop a console or CLI deletion.
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  # Evidence is contemporaneous, so an overwrite destroys something that cannot
  # be produced again. Versions are what make that recoverable. No
  # noncurrent-version expiry is set, because the bounded retention rule is not
  # decided yet and a guessed rule would delete evidence on a schedule nobody
  # approved.
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.evidence.arn,
          "${aws_s3_bucket.evidence.arn}/*",
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
