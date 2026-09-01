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

# The second and third repositories of the ADR-0009 registry. shipping and quote
# are project-built application services, so the astroshop/ workload-artifact
# convention that named the repository above governs these two as well.
#
# Every hardening argument carries the same reasoning as the checkout repository
# above and is not restated: immutable commit-derived tags, an AWS-managed
# key at rest, force_delete refusing a destroy while images remain, and native
# scan-on-push left off because Trivy gates in the pipeline before an artifact
# reaches the registry. The project pipeline runs that Trivy gate for both of
# these services, so the reason the setting is off holds here rather than being
# inherited by assumption.
resource "aws_ecr_repository" "shipping" {
  name                 = "astroshop/shipping"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Component = "artifact-registry"
  }
}

# The same count-based bound as the repository above, for the same ADR-0009
# reason: immutable tags mean no push ever reclaims the storage an earlier one
# took. The count of ten is the established project bound carried across rather
# than a second figure derived here, so the registry keeps one retention rule to
# reason about. The owner-review trigger the README records before an eleventh
# tagged image belongs to the checkout first-digest artifact and is not restated
# as an obligation of this repository.
resource "aws_ecr_lifecycle_policy" "shipping" {
  repository = aws_ecr_repository.shipping.name

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

resource "aws_ecr_repository" "quote" {
  name                 = "astroshop/quote"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Component = "artifact-registry"
  }
}

resource "aws_ecr_lifecycle_policy" "quote" {
  repository = aws_ecr_repository.quote.name

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

# The mirror destination for the OpenTelemetry Collector image, so no pod start
# depends on an external registry at runtime.
#
# platform/ rather than astroshop/. The astroshop/ prefix is the workload-artifact
# namespace for services this project builds from source, and the Collector is
# neither: it is a third-party platform component whose pinning authority is
# ADR-0006 through ADR-0010 rather than the ADR-0012 workload rules. Naming it
# astroshop/ would file a platform input under the workload convention and make
# the namespace stop meaning anything. Like the slash in astroshop/, this one is
# part of the name and creates no policy namespace and no security boundary.
#
# The hardening controls that apply carry the same reasoning as the repositories
# above: immutable tags, an AWS-managed key at rest, and force_delete refusing a
# destroy while images remain.
#
# scan_on_push stays off, consistent with every repository above and for the same
# reason: nothing in this project gates on registry-native findings, so enabling
# it would open a second stream no gate reads. The recorded pre-RW-3 requirement
# that the Collector image be scanned or verified is a separate obligation with
# its own mechanism, and this setting neither satisfies nor obstructs it.
#
# No lifecycle policy, deliberately. The count-based rule on the repositories
# above bounds a continuously republished application artifact stream, which this
# is not: the Collector is consumed by immutable digest, so expiring an image on
# a tag count could delete a digest a running deployment or a recovery still
# references. Copying that rule for symmetry would be inventing retention policy,
# so the bound stays an owner decision rather than an assumption made here.
#
# No CI push permission either. This repository is deliberately absent from the
# GitLab publication role below, which stays scoped to the three application
# repositories. The mirror mechanism is reviewed separately.
resource "aws_ecr_repository" "collector" {
  name                 = "platform/opentelemetry-collector"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Component = "artifact-registry"
  }
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
# statement takes the ARNs Terraform computed for the three repositories above,
# so no account ID is written here and the grant cannot widen if a repository
# name changes.
#
# One role rather than three. The sub claim this role trusts carries the project
# and the ref and nothing that separates one service's pipeline from another's,
# and checkout, shipping and quote all publish from the same project on the same
# branch. Three roles would therefore carry three byte-identical trust
# conditions, so any job able to assume one could assume all three: separation in
# name with none in fact, at three times the surface to keep in step. The
# resource list below is where the real boundary sits, and it enumerates exactly
# the repositories the project pipeline publishes.
#
# The role and policy names still say checkout. They are legacy labels for what
# is now the shared CI publication identity: renaming an IAM role replaces it,
# so the address is kept stable deliberately rather than made tidy.
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
        Resource = [
          aws_ecr_repository.checkout.arn,
          aws_ecr_repository.shipping.arn,
          aws_ecr_repository.quote.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
    ]
  })
}
