mock_provider "aws" {}

variables {
  allowed_account_id = "000000000000"
  operator_cidr      = "203.0.113.10/32"
}

# The policy names the dev VPC's ARN, which a mocked plan leaves unknown.
override_resource {
  target          = aws_vpc.dev
  override_during = plan
  values = {
    arn = "arn:aws:ec2:us-east-1:000000000000:vpc/vpc-0123456789abcdef0"
  }
}

run "worker_mode_creates_no_public_entry_identity" {
  command = plan

  assert {
    condition = 0 == sum([
      length(aws_iam_role.record_controller), length(aws_iam_role_policy.record_controller), length(aws_eks_pod_identity_association.record_controller),
      length(aws_iam_role.aws_load_balancer_controller), length(aws_iam_role_policy.aws_load_balancer_controller), length(aws_eks_pod_identity_association.aws_load_balancer_controller),
    ])
    error_message = "Without public_entry_enabled, worker mode must create no public-entry identity."
  }
}

run "node_measurement_creates_no_public_entry_identity" {
  command = plan

  variables {
    node_measurement_only = true
  }

  assert {
    condition = 0 == sum([
      length(aws_iam_role.record_controller), length(aws_iam_role_policy.record_controller), length(aws_eks_pod_identity_association.record_controller),
      length(aws_iam_role.aws_load_balancer_controller), length(aws_iam_role_policy.aws_load_balancer_controller), length(aws_eks_pod_identity_association.aws_load_balancer_controller),
    ])
    error_message = "Node measurement must create no public-entry identity."
  }
}

run "observation_mode_creates_no_public_entry_identity" {
  command = plan

  variables {
    worker_capacity_enabled = false
  }

  assert {
    condition = 0 == sum([
      length(aws_iam_role.record_controller), length(aws_iam_role_policy.record_controller), length(aws_eks_pod_identity_association.record_controller),
      length(aws_iam_role.aws_load_balancer_controller), length(aws_iam_role_policy.aws_load_balancer_controller), length(aws_eks_pod_identity_association.aws_load_balancer_controller),
    ])
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

run "public_entry_creates_the_load_balancer_controller_identity" {
  command = plan

  variables {
    public_entry_enabled  = true
    public_hosted_zone_id = "Z0000000000EXAMPLE"
    public_domain         = "example.com"
  }

  assert {
    condition     = aws_iam_role.aws_load_balancer_controller[0].name == "cloud-platform-reference-dev-aws-load-balancer-controller" && aws_eks_pod_identity_association.aws_load_balancer_controller[0].namespace == "kube-system" && aws_eks_pod_identity_association.aws_load_balancer_controller[0].service_account == "aws-load-balancer-controller"
    error_message = "The load balancer controller role must be bound to the aws-load-balancer-controller ServiceAccount in kube-system."
  }

  assert {
    condition     = jsondecode(aws_iam_role.aws_load_balancer_controller[0].assume_role_policy).Statement == [{ Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Principal = { Service = "pods.eks.amazonaws.com" } }]
    error_message = "The load balancer controller role must trust only the Pod Identity service principal."
  }

  assert {
    condition = alltrue([
      for action in flatten([for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement : statement.Action]) :
      action != "iam:CreateServiceLinkedRole" && !startswith(action, "waf-regional:") && !startswith(action, "wafv2:") && !startswith(action, "shield:")
    ])
    error_message = "The load balancer controller must not create a service-linked role or manage WAF or Shield."
  }

  assert {
    condition = length([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement : statement
      if contains(flatten([statement.Action]), "ec2:CreateSecurityGroup")
      ]) == 2 && length([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement : statement
      if contains(flatten([statement.Action]), "ec2:CreateSecurityGroup") && statement.Resource == aws_vpc.dev.arn
      ]) == 1 && length([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement : statement
      if contains(flatten([statement.Action]), "ec2:CreateSecurityGroup") && statement.Resource == "arn:aws:ec2:*:*:security-group/*" && try(statement.Condition.StringEquals["aws:RequestTag/elbv2.k8s.aws/cluster"], null) == aws_eks_cluster.dev.name
    ]) == 1
    error_message = "CreateSecurityGroup must have separate permissions for the exact dev VPC ARN and security-group resources requiring this cluster's ownership tag."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement :
      try(statement.Condition.ArnEquals["ec2:Vpc"], null) == aws_vpc.dev.arn && anytrue([
        for key in ["aws:ResourceTag/aws:eks:cluster-name", "aws:ResourceTag/elbv2.k8s.aws/cluster"] :
        try(statement.Condition.StringEquals[key], null) == aws_eks_cluster.dev.name
      ])
      if length(setintersection(flatten([statement.Action]), ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"])) > 0
    ])
    error_message = "Ingress-rule changes and deletion must name this cluster's exact tag value and the dev VPC."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement :
      (try(statement.Condition.StringEquals["ec2:CreateAction"], null) == "CreateSecurityGroup" && try(statement.Condition.StringEquals["aws:RequestTag/elbv2.k8s.aws/cluster"], null) == aws_eks_cluster.dev.name) ||
      (try(statement.Condition.StringEquals["aws:ResourceTag/elbv2.k8s.aws/cluster"], null) == aws_eks_cluster.dev.name && try(statement.Condition.Null["aws:TagKeys"], null) == "false" && contains(try(statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"], []), "elbv2.k8s.aws/cluster"))
      if length(setintersection(flatten([statement.Action]), ["ec2:CreateTags", "ec2:DeleteTags"])) > 0
    ])
    error_message = "Security-group tags may be set at creation with this cluster's tag, or changed on its own groups only when the request names keys and none is the ownership key."
  }

  assert {
    condition = length([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement : statement
      if contains(flatten([statement.Action]), "elasticloadbalancing:CreateLoadBalancer") || contains(flatten([statement.Action]), "elasticloadbalancing:CreateTargetGroup")
      ]) > 0 && alltrue([
      for statement in jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy).Statement :
      try(statement.Condition.Null["aws:RequestTag/elbv2.k8s.aws/cluster"], null) == "false"
      if contains(flatten([statement.Action]), "elasticloadbalancing:CreateLoadBalancer") || contains(flatten([statement.Action]), "elasticloadbalancing:CreateTargetGroup")
    ])
    error_message = "Load balancer and target group creation must keep the upstream elbv2.k8s.aws/cluster request-tag condition."
  }

  assert {
    condition     = length(jsonencode(jsondecode(aws_iam_role_policy.aws_load_balancer_controller[0].policy))) <= 10240
    error_message = "The policy must fit the 10,240-character inline role policy quota."
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
