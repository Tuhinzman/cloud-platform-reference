# No _version resource: it would write the secret value into Terraform state.
resource "aws_secretsmanager_secret" "workload" {
  name                    = "cloud-platform-reference-dev-workload-secret"
  recovery_window_in_days = 7

  tags = {
    Component = "identity"
    Lifecycle = "persistent"
  }
}

resource "aws_secretsmanager_secret" "argocd_gitops_deploy_key" {
  name                    = "cloud-platform-reference-dev-argocd-gitops-deploy-key"
  recovery_window_in_days = 7

  tags = {
    Component = "identity"
    Lifecycle = "persistent"
  }
}

resource "aws_ssm_parameter" "workload" {
  name  = "cloud-platform-reference-dev-workload-environment"
  type  = "String"
  tier  = "Standard"
  value = "dev"

  tags = {
    Component = "identity"
    Lifecycle = "persistent"
  }
}
