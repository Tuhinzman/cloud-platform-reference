mock_provider "aws" {}

variables {
  allowed_account_id = "000000000000"
  operator_cidr      = "203.0.113.10/32"
}

run "node_measurement_schedules_no_pod" {
  command = plan

  variables {
    worker_capacity_enabled = true
    node_measurement_only   = true
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 0 && length(aws_eks_addon.kube_proxy) == 0 && length(aws_eks_addon.pod_identity_agent) == 0
    error_message = "Node measurement must create no vpc-cni, kube-proxy or Pod Identity agent add-on."
  }

  assert {
    condition     = aws_eks_addon.coredns.configuration_values == jsonencode({ replicaCount = 0 }) && aws_eks_addon.coredns.timeouts.create == "5m"
    error_message = "Node measurement must hold CoreDNS at zero replicas with the bounded create wait."
  }

  assert {
    condition     = length(aws_eks_pod_identity_association.external_secrets) == 0
    error_message = "Node measurement must create no Pod Identity association."
  }

  assert {
    condition     = length(aws_eks_node_group.dev) == 1 && aws_eks_node_group.dev[0].release_version == "1.36.4-20260923"
    error_message = "Node measurement must create the node group on the pinned AMI release."
  }
}

run "worker_mode_keeps_the_runtime_set" {
  command = plan

  variables {
    worker_capacity_enabled = true
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 1 && length(aws_eks_addon.kube_proxy) == 1 && length(aws_eks_addon.pod_identity_agent) == 1
    error_message = "Worker mode must keep the vpc-cni, kube-proxy and Pod Identity agent add-ons."
  }

  # configuration_values is computed when unset, so the default replica count is checked by the
  # plan contract; its bounded wait, set together with the zero replicas, is known here.
  assert {
    condition     = aws_eks_addon.coredns.timeouts.create == null && length(aws_eks_pod_identity_association.external_secrets) == 1
    error_message = "Worker mode must keep CoreDNS without the zero-replica wait, and the Pod Identity association."
  }
}

run "observation_mode_keeps_the_four_add_ons_without_a_node" {
  command = plan

  variables {
    worker_capacity_enabled = false
  }

  assert {
    condition     = length(aws_eks_addon.vpc_cni) == 1 && length(aws_eks_addon.kube_proxy) == 1 && length(aws_eks_addon.pod_identity_agent) == 1 && length(aws_eks_node_group.dev) == 0
    error_message = "Observation mode must keep the four add-ons and create no node group."
  }

  assert {
    condition     = aws_eks_addon.coredns.configuration_values == jsonencode({ replicaCount = 0 })
    error_message = "Observation mode must hold CoreDNS at zero replicas."
  }
}

run "node_measurement_needs_worker_capacity" {
  command = plan

  variables {
    worker_capacity_enabled = false
    node_measurement_only   = true
  }

  expect_failures = [var.node_measurement_only]
}
