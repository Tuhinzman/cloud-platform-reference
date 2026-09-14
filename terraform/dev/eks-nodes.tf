resource "aws_iam_role" "eks_node" {
  name = "cloud-platform-reference-dev-eks-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Component = "runtime"
  }
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_pull" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# Node-group tags and provider default_tags never reach the instances or volumes.
resource "aws_launch_template" "eks_node" {
  name_prefix = "cloud-platform-reference-dev-node-"

  # disk_size is unavailable on a node group that uses a launch template.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # hop_limit 1 answers the host and drops pods; AWS often suggests 2.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Project     = "cloud-platform-reference"
      Environment = "dev"
      Component   = "runtime"
      Lifecycle   = "ephemeral"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
      Name        = "cloud-platform-reference-dev-node"
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Project     = "cloud-platform-reference"
      Environment = "dev"
      Component   = "runtime"
      Lifecycle   = "ephemeral"
      Owner       = "platform-engineer"
      ManagedBy   = "terraform"
    }
  }

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_node_group" "dev" {
  cluster_name    = aws_eks_cluster.dev.name
  node_group_name = "cloud-platform-reference-dev-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  instance_types = ["m6a.large"]
  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  # latest_version makes a template edit a rolling node replacement.
  launch_template {
    id      = aws_launch_template.eks_node.id
    version = aws_launch_template.eks_node.latest_version
  }

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Component = "runtime"
  }

  # Node registration and image pulls leave through the NAT route.
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr_pull,
    aws_route.private_default,
  ]
}
