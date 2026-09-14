# No thumbprint_list: AWS verifies the GitLab JWKS certificate itself.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url            = "https://gitlab.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Component = "identity"
  }
}

# A job that declares an environment no longer matches this sub claim.
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

# Names say checkout for history; renaming an IAM role replaces it.
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
      # Registry-level call; it accepts no repository ARN.
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
    ]
  })
}
