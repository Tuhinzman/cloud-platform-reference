# One repository per owned service, created when it enters the delivery path (ADR-0009);
# ADR-0013 requires each persistent foundation to show it is still needed.
locals {
  workload_repositories = toset([
    "checkout",
    "shipping",
    "quote",
    "frontend-proxy",
    "image-provider",
    "cart",
    "frontend",
    "payment",
    "product-catalog",
  ])
}

resource "aws_ecr_repository" "workload" {
  for_each = local.workload_repositories

  name                 = "astroshop/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  # Off deliberately: Trivy gates in the pipeline before an image is pushed.
  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Component = "artifact-registry"
  }
}

resource "aws_ecr_lifecycle_policy" "workload" {
  for_each = local.workload_repositories

  repository = aws_ecr_repository.workload[each.key].name

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

# The Collector stays its own resource rather than joining the set above. It is a mirrored
# platform component, not a workload artifact this project builds, and keeping it separate is
# what makes the CI push policy's exclusion of it structural instead of a list that happens to
# omit it. No lifecycle policy: the Collector is consumed by digest, not by tag count.
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

# The three original repositories hold published images, including the digest the GitOps
# desired state references. These blocks move their state addresses into the set above without
# touching anything in AWS. They can be removed once the move has been applied.
moved {
  from = aws_ecr_repository.checkout
  to   = aws_ecr_repository.workload["checkout"]
}

moved {
  from = aws_ecr_repository.shipping
  to   = aws_ecr_repository.workload["shipping"]
}

moved {
  from = aws_ecr_repository.quote
  to   = aws_ecr_repository.workload["quote"]
}

moved {
  from = aws_ecr_lifecycle_policy.checkout
  to   = aws_ecr_lifecycle_policy.workload["checkout"]
}

moved {
  from = aws_ecr_lifecycle_policy.shipping
  to   = aws_ecr_lifecycle_policy.workload["shipping"]
}

moved {
  from = aws_ecr_lifecycle_policy.quote
  to   = aws_ecr_lifecycle_policy.workload["quote"]
}
