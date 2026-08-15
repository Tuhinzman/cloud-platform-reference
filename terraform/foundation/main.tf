provider "aws" {
  region = "us-east-1"

  # Any account other than the dedicated project account is a hard stop, so the
  # provider verifies the caller's account before it does anything. A wrong
  # credential then fails at the first API call instead of creating a project
  # foundation somewhere it does not belong.
  allowed_account_ids = [var.allowed_account_id]

  # The six mandatory tags of ADR-0013. The bucket, the ECR repository, the
  # OIDC provider and the CI role are the taggable AWS resources here. The
  # bucket's four configuration resources, the repository's lifecycle policy
  # and the role's inline policy are sub-resources and carry no tags of their
  # own. Component is "evidence-store" as the root default, and the resources
  # that are not evidence storage override it on themselves, to
  # "artifact-registry" for the registry and "identity" for the federation and
  # the CI role, because cost attribution reads this tag.
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

# The account's trust anchor for GitLab.com-issued ID tokens. ADR-0009 puts
# pipeline identity on OIDC federation, so CI exchanges a job token for
# short-lived STS credentials and no long-lived AWS credential exists anywhere
# in the pipeline. The URL is the issuer claim GitLab.com writes into every
# token, and the audience is the value the pipeline's id_tokens block must
# request.
#
# No thumbprint_list. AWS verifies the JWKS endpoint's TLS certificate against
# its own library of trusted root certificate authorities for GitLab, so a
# hand-maintained thumbprint would add a rotation duty whose only effect on
# expiry is to break role assumption.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url            = "https://gitlab.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Component = "identity"
  }
}

# The automation identity class of ADR-0005: a dedicated non-human role holding
# no credential of its own, assumed only through web identity federation.
#
# The trust is deliberately narrow. The sub claim GitLab issues carries the
# project ID and the ref, so pinning it to this project on branch main means a
# job in another project, on another branch, on a tag, or in a merge-request
# pipeline cannot assume this role even though it presents a valid GitLab token.
# The aud condition pins the audience alongside it, because a token minted for a
# different service must not be replayable here.
#
# Two consequences the pipeline has to respect. A job that declares an
# environment gets extra fields in its sub claim, which no longer equals the
# string below, so the push job declares none. And because the project ID is
# immutable, the trust stays bound to this same project across a rename or a
# transfer, where a path would either stop matching or, once reused by another
# project, name something this role never meant to trust.
resource "aws_iam_role" "ci_checkout" {
  name = "cloud-platform-reference-shared-ci-checkout"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Condition = {
          StringEquals = {
            "gitlab.com:aud" = "sts.amazonaws.com"
            "gitlab.com:sub" = "project_id:${var.gitlab_project_id}:ref_type:branch:ref:main"
          }
        }
      },
    ]
  })

  tags = {
    Component = "identity"
  }
}

# Push side only, and inline because one role consumes it. The repository
# statement takes the ARN Terraform computed for the repository above, so no
# account ID is written here and the grant cannot widen if the repository name
# changes.
#
# ecr:GetAuthorizationToken stands alone on "*" because it is a registry-level
# call that accepts no repository ARN. That is the only reason anything here is
# unscoped, and it does not widen the repository actions beside it. Nothing
# grants repository deletion, lifecycle-policy mutation, IAM, or any other
# service.
#
# This is the minimum credible set for authenticating, uploading layers and
# publishing a manifest. It is a starting hypothesis until the first pipeline
# run shows what the push actually calls.
resource "aws_iam_role_policy" "ci_checkout_ecr_push" {
  name = "cloud-platform-reference-shared-ci-checkout-ecr-push"
  role = aws_iam_role.ci_checkout.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        Resource = aws_ecr_repository.checkout.arn
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
    ]
  })
}
