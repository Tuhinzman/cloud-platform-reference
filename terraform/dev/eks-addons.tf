# OVERWRITE settles the field conflicts of adopting the EKS-installed copies.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.22.3-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "coredns"
  addon_version               = "v1.14.3-eksbuild.3"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }

  # CoreDNS needs schedulable capacity before it can become healthy.
  depends_on = [aws_eks_node_group.dev]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.36.0-eksbuild.13"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.dev.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.10-eksbuild.3"

  tags = {
    Component = "runtime"
  }
}
