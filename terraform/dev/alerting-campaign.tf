resource "aws_sns_topic" "alerting" {
  count = var.alerting_campaign_enabled ? 1 : 0

  name = "cloud-platform-reference-dev-alerting"

  tags = {
    Component = "observability"
  }
}

# sensitive redacts output only; remote state stores the endpoint in clear.
resource "aws_sns_topic_subscription" "alerting_email" {
  count = var.alerting_campaign_enabled && var.alerting_email_subscription_enabled ? 1 : 0

  topic_arn = aws_sns_topic.alerting[0].arn
  protocol  = "email"
  endpoint  = var.alerting_email_endpoint
}

resource "aws_iam_role" "grafana_alerting" {
  count = var.alerting_campaign_enabled ? 1 : 0

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

resource "aws_iam_role_policy" "grafana_alerting" {
  count = var.alerting_campaign_enabled ? 1 : 0

  name = "cloud-platform-reference-dev-grafana-alerting-publish"
  role = aws_iam_role.grafana_alerting[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.alerting[0].arn]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "grafana_alerting" {
  count = var.alerting_campaign_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.dev.name
  namespace       = "observability"
  service_account = "grafana"
  role_arn        = aws_iam_role.grafana_alerting[0].arn

  tags = {
    Component = "identity"
  }
}
