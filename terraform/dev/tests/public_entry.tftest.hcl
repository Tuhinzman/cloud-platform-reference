mock_provider "aws" {}

variables {
  allowed_account_id = "000000000000"
  operator_cidr      = "203.0.113.10/32"
}

run "worker_mode_creates_no_public_entry_identity" {
  command = plan

  assert {
    condition     = length(aws_iam_role.record_controller) + length(aws_iam_role_policy.record_controller) + length(aws_eks_pod_identity_association.record_controller) == 0
    error_message = "Without public_entry_enabled, worker mode must create no public-entry identity."
  }
}

run "node_measurement_creates_no_public_entry_identity" {
  command = plan

  variables {
    node_measurement_only = true
  }

  assert {
    condition     = length(aws_iam_role.record_controller) + length(aws_iam_role_policy.record_controller) + length(aws_eks_pod_identity_association.record_controller) == 0
    error_message = "Node measurement must create no public-entry identity."
  }
}

run "observation_mode_creates_no_public_entry_identity" {
  command = plan

  variables {
    worker_capacity_enabled = false
  }

  assert {
    condition     = length(aws_iam_role.record_controller) + length(aws_iam_role_policy.record_controller) + length(aws_eks_pod_identity_association.record_controller) == 0
    error_message = "Observation mode must create no public-entry identity."
  }
}

run "public_entry_creates_the_record_controller_identity" {
  command = plan

  variables {
    public_entry_enabled  = true
    public_hosted_zone_id = "Z0000000000EXAMPLE"
    public_domain         = "example.com"
  }

  assert {
    condition     = aws_iam_role.record_controller[0].name == "cloud-platform-reference-dev-record-controller" && aws_eks_pod_identity_association.record_controller[0].namespace == "external-dns" && aws_eks_pod_identity_association.record_controller[0].service_account == "external-dns"
    error_message = "The record controller role must be bound to the external-dns ServiceAccount in the external-dns namespace."
  }

  assert {
    condition     = jsondecode(aws_iam_role.record_controller[0].assume_role_policy).Statement == [{ Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Principal = { Service = "pods.eks.amazonaws.com" } }]
    error_message = "The record controller role must trust only the Pod Identity service principal."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.record_controller[0].policy).Statement[0] == {
      Effect   = "Allow"
      Action   = ["route53:ChangeResourceRecordSets"]
      Resource = ["arn:aws:route53:::hostedzone/Z0000000000EXAMPLE"]
      Condition = {
        "ForAllValues:StringEquals" = {
          "route53:ChangeResourceRecordSetsNormalizedRecordNames" = ["dev.example.com", "a-dev.example.com"]
          "route53:ChangeResourceRecordSetsRecordTypes"           = ["A", "TXT"]
        }
        Null = {
          "route53:ChangeResourceRecordSetsNormalizedRecordNames" = "false"
          "route53:ChangeResourceRecordSetsRecordTypes"           = "false"
        }
      }
    }
    error_message = "Record changes must be limited to the one zone, the environment's two names and the A and TXT types."
  }

  assert {
    condition     = sort(flatten([for statement in jsondecode(aws_iam_role_policy.record_controller[0].policy).Statement : statement.Action])) == sort(["route53:ChangeResourceRecordSets", "route53:ListHostedZones", "route53:ListResourceRecordSets"])
    error_message = "The record controller policy must grant exactly the three Route 53 actions ExternalDNS calls."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.record_controller[0].policy).Statement :
      statement.Resource == (statement.Action == ["route53:ListHostedZones"] ? ["*"] : ["arn:aws:route53:::hostedzone/Z0000000000EXAMPLE"])
    ])
    error_message = "Every grant except ListHostedZones must name the one zone, and only ListHostedZones may be account-wide."
  }
}

run "public_entry_needs_worker_capacity" {
  command = plan

  variables {
    worker_capacity_enabled = false
    public_entry_enabled    = true
    public_hosted_zone_id   = "Z0000000000EXAMPLE"
    public_domain           = "example.com"
  }

  expect_failures = [var.public_entry_enabled]
}

run "public_entry_refuses_node_measurement" {
  command = plan

  variables {
    node_measurement_only = true
    public_entry_enabled  = true
    public_hosted_zone_id = "Z0000000000EXAMPLE"
    public_domain         = "example.com"
  }

  expect_failures = [var.public_entry_enabled]
}

run "public_entry_needs_the_zone_id" {
  command = plan

  variables {
    public_entry_enabled = true
    public_domain        = "example.com"
  }

  expect_failures = [var.public_hosted_zone_id]
}

run "public_entry_needs_the_domain" {
  command = plan

  variables {
    public_entry_enabled  = true
    public_hosted_zone_id = "Z0000000000EXAMPLE"
  }

  expect_failures = [var.public_domain]
}

run "rejects_a_zone_id_with_its_path_prefix" {
  command = plan

  variables {
    public_entry_enabled  = true
    public_hosted_zone_id = "/hostedzone/Z0000000000EXAMPLE"
    public_domain         = "example.com"
  }

  expect_failures = [var.public_hosted_zone_id]
}

run "rejects_a_domain_with_a_trailing_dot" {
  command = plan

  variables {
    public_entry_enabled  = true
    public_hosted_zone_id = "Z0000000000EXAMPLE"
    public_domain         = "example.com."
  }

  expect_failures = [var.public_domain]
}
