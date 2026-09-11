# ---------------------------------------------------------------------------
# REQ-015 alerting campaign resources.
#
# Campaign scope, owner decision 2026-09-11: these resources exist for the
# bounded REQ-015 alerting window only. They are created with the Dev runtime
# and destroyed with it, so they join the targeted destroy set and the
# zero-residual census of that window. None of them is a persistent foundation,
# and none survives to avoid a later email confirmation.
#
# Delivery path: Grafana unified alerting -> EKS Pod Identity -> Amazon SNS ->
# one email subscription. No static credential, no Secrets Manager entry, no
# SMTP, no webhook. The Grafana pod obtains SNS publish permission through the
# association below; the SDK inside Grafana resolves it from the Pod Identity
# credential endpoint the pod_identity_agent addon provides.
#
# The email endpoint is a private execution input: a variable with no committed
# value, marked sensitive so plan and apply output redact it. The subscription
# resource is created only when the operator enables it at execution time, so
# this root plans and validates without any address present.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerting" {
  name = "cloud-platform-reference-dev-alerting"

  tags = {
    Component = "observability"
  }
}

# Email subscriptions start in PendingConfirmation until the recipient confirms;
# the confirmation is an owner action at the window's pre-open step. Deleting the
# topic removes its subscriptions, which is what the campaign teardown relies on.
resource "aws_sns_topic_subscription" "alerting_email" {
  count = var.alerting_email_subscription_enabled ? 1 : 0

  topic_arn = aws_sns_topic.alerting.arn
  protocol  = "email"
  endpoint  = var.alerting_email_endpoint
}

# One role for one pod identity. The trust names only the generic Pod Identity
# service principal, as the other Pod Identity roles in this root do. Unlike
# those roles this one is campaign-scoped and leaves with the window.
resource "aws_iam_role" "grafana_alerting" {
  name = "cloud-platform-reference-dev-grafana-alerting"

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

# Exactly one action on exactly one topic. The Resource is the ARN Terraform
# computed for the topic above, so no account ID is written here and the grant
# cannot reach any other topic.
resource "aws_iam_role_policy" "grafana_alerting" {
  name = "cloud-platform-reference-dev-grafana-alerting-publish"
  role = aws_iam_role.grafana_alerting.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.alerting.arn]
      },
    ]
  })
}

# The namespace and ServiceAccount are the ones the Grafana chart renders for
# the grafana-dev Application (release grafana in namespace observability). The
# association must exist before the Grafana pod starts, otherwise the pod comes
# up without the identity and needs a restart to pick it up; the window's
# bootstrap order accounts for that.
resource "aws_eks_pod_identity_association" "grafana_alerting" {
  cluster_name    = aws_eks_cluster.dev.name
  namespace       = "observability"
  service_account = "grafana"
  role_arn        = aws_iam_role.grafana_alerting.arn

  tags = {
    Component = "identity"
  }
}
