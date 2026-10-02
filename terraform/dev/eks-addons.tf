# The cluster installs no self-managed copies, so OVERWRITE has nothing to adopt; it only
# settles a conflicting object if one ever appears.
resource "aws_eks_addon" "vpc_cni" {
  count = var.node_measurement_only ? 0 : 1

  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "vpc-cni"
  addon_version               = "v1.23.1-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "coredns"
  addon_version               = "v1.14.6-eksbuild.4"
  resolve_conflicts_on_create = "OVERWRITE"

  # Observation mode has no node and node measurement runs no pod: zero replicas creates the
  # Deployment without scheduling a pod.
  configuration_values = var.worker_capacity_enabled && !var.node_measurement_only ? null : jsonencode({ replicaCount = 0 })

  tags = {
    Component = "runtime"
  }

  # CoreDNS needs schedulable capacity before it can become healthy.
  depends_on = [aws_eks_node_group.dev]

  # The provider waits on DEGRADED as if it were pending; with no schedulable node that wait
  # would run out the 20-minute default.
  timeouts {
    create = var.worker_capacity_enabled && !var.node_measurement_only ? null : "5m"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.node_measurement_only ? 0 : 1

  cluster_name                = aws_eks_cluster.dev.name
  addon_name                  = "kube-proxy"
  addon_version               = "v1.36.0-eksbuild.25"
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Component = "runtime"
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  count = var.node_measurement_only ? 0 : 1

  cluster_name  = aws_eks_cluster.dev.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.4.0-eksbuild.2"

  tags = {
    Component = "runtime"
  }
}
