locals {
  # The environment hostname and the ownership marker ExternalDNS v0.23.0 writes beside its A
  # record. Its values must exclude AAAA and set no TXT prefix or suffix, or its writes are denied.
  record_controller_names = var.public_domain == null ? [] : ["dev.${var.public_domain}", "a-dev.${var.public_domain}"]
}

resource "aws_iam_role" "record_controller" {
  count = var.public_entry_enabled ? 1 : 0

  name = "cloud-platform-reference-dev-record-controller"

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
  }
}

resource "aws_iam_role_policy" "record_controller" {
  count = var.public_entry_enabled ? 1 : 0

  name = "cloud-platform-reference-dev-record-controller-records"
  role = aws_iam_role.record_controller[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/${var.public_hosted_zone_id}"]
        # ForAllValues alone allows a request that carries no value for a key; Null refuses it.
        Condition = {
          "ForAllValues:StringEquals" = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = local.record_controller_names
            "route53:ChangeResourceRecordSetsRecordTypes"           = ["A", "TXT"]
          }
          Null = {
            "route53:ChangeResourceRecordSetsNormalizedRecordNames" = "false"
            "route53:ChangeResourceRecordSetsRecordTypes"           = "false"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/${var.public_hosted_zone_id}"]
      },
      # ExternalDNS lists every zone before it applies its zone filter, and this action cannot be
      # scoped to a resource. It returns zone metadata, never records.
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones"]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "record_controller" {
  count = var.public_entry_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.dev.name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.record_controller[0].arn

  tags = {
    Component = "identity"
  }
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  count = var.public_entry_enabled ? 1 : 0

  name = "cloud-platform-reference-dev-aws-load-balancer-controller"

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
  }
}

# Upstream v3.5.0 less its service-linked-role, WAF and Shield grants; the README records the source.
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  count = var.public_entry_enabled ? 1 : 0

  name   = "cloud-platform-reference-dev-aws-load-balancer-controller-ingress"
  role   = aws_iam_role.aws_load_balancer_controller[0].name
  policy = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  count = var.public_entry_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.dev.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_load_balancer_controller[0].arn

  tags = {
    Component = "identity"
  }
}
