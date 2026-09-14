resource "aws_ecr_repository" "checkout" {
  name                 = "astroshop/checkout"
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

resource "aws_ecr_lifecycle_policy" "checkout" {
  repository = aws_ecr_repository.checkout.name

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

# No lifecycle policy: the Collector is consumed by digest, not by tag count.
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
