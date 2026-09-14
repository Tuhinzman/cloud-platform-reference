resource "aws_iam_role" "workload" {
  name = "cloud-platform-reference-dev-workload"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "identity"
    Lifecycle = "persistent"
  }
}

resource "aws_iam_role_policy" "workload" {
  name = "cloud-platform-reference-dev-workload-read"
  role = aws_iam_role.workload.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.workload.arn
      },
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.workload.arn
      },
    ]
  })
}

resource "aws_iam_role" "external_secrets" {
  name = "cloud-platform-reference-dev-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession",
        ]
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "identity"
    Lifecycle = "persistent"
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "cloud-platform-reference-dev-external-secrets-read"
  role = aws_iam_role.external_secrets.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          aws_secretsmanager_secret.workload.arn,
          aws_secretsmanager_secret.argocd_gitops_deploy_key.arn,
        ]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.dev.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn

  tags = {
    Component = "identity"
  }
}
