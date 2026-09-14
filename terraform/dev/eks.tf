resource "aws_iam_role" "eks_cluster" {
  name = "cloud-platform-reference-dev-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "runtime"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "dev" {
  name     = "cloud-platform-reference-dev"
  version  = "1.36"
  role_arn = aws_iam_role.eks_cluster.arn

  deletion_protection = false

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]

    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = [var.operator_cidr]
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Component = "runtime"
  }

  # The cluster references the role, not its policy attachment.
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
