provider "aws" {
  region = "us-east-1"

  # Any account other than the dedicated project account is a hard stop, so the
  # provider verifies the caller's account before it does anything. A wrong
  # credential then fails at the first API call instead of creating a project
  # foundation somewhere it does not belong.
  allowed_account_ids = [var.allowed_account_id]

  # The six mandatory tags of ADR-0013. The bucket and the ECR repository are
  # the taggable AWS resources here, so these reach those two. The bucket's
  # four configuration resources and the repository's lifecycle policy are
  # sub-resources and carry no tags of their own. Component is "evidence-store"
  # as the root default, and the repository overrides it to "artifact-registry"
  # on itself, because cost attribution reads this tag and a registry is not
  # evidence storage.
  #
  # Environment is "shared" because every foundation here is persistent and
  # shared and belongs to none of the three environment roles. It is the same
  # value the state backend carries. Two foundations under different values
  # would break the cost attribution REQ-019 requires, because orphan scans and
  # cost grouping read this tag.
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

resource "aws_ecr_repository" "checkout" {
  # The first repository of the ADR-0009 registry: one repository per owned
  # service, created when that service enters the implemented delivery path,
  # and checkout is the approved first-digest service. astroshop/ is the
  # workload-artifact naming convention. The slash is part of the name and
  # nothing more: it creates no policy namespace and no security boundary.
  name = "astroshop/checkout"

  # ADR-0009 derives tags from the source commit and makes the digest the
  # artifact's identity, so the registry must refuse a push that would move
  # an existing tag onto a different image.
  image_tag_mutability = "IMMUTABLE"

  # Refuse to delete stored images in order to complete a repository destroy.
  # Unlike the evidence bucket there is no prevent_destroy here: images are
  # rebuilt from source rather than restored, the ADR-0009 decommission path
  # is deletion once no environment references them, and this refusal already
  # blocks the destroy that matters.
  force_delete = false

  # Same at-rest model as the evidence bucket: an AWS-managed key, because no
  # obligation here needs a customer-managed key's cost and lifecycle.
  encryption_configuration {
    encryption_type = "AES256"
  }

  # Off deliberately. Trivy is the one primary scanning platform (ADR-0009)
  # and gates in the pipeline before an artifact reaches the registry, so
  # registry-native scanning would only open a second findings stream that no
  # gate reads.
  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Component = "artifact-registry"
  }
}

resource "aws_ecr_lifecycle_policy" "checkout" {
  repository = aws_ecr_repository.checkout.name

  # ADR-0009 requires registry storage to stay bounded, and immutable
  # commit-derived tags mean every published build adds an image that no
  # overwrite ever reclaims. The approved bound is count-based: retain the
  # newest ten tagged images, expire older ones only once the count exceeds
  # ten. tagStatus "tagged" must carry a tag pattern, and "*" matches every
  # tagged image, which is this repository's entire published population.
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the newest 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
