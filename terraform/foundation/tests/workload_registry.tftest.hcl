mock_provider "aws" {}

variables {
  allowed_account_id   = "000000000000"
  evidence_bucket_name = "example-platform-evidence-000000"
  gitlab_project_id    = 12345678
  public_domain        = "example.com"

  # The justified project-built inventory: 15 application services and 2 configured components.
  expected_workload_repositories = [
    "accounting",
    "ad",
    "cart",
    "checkout",
    "currency",
    "email",
    "flagd-ui",
    "fraud-detection",
    "frontend",
    "frontend-proxy",
    "image-provider",
    "payment",
    "product-catalog",
    "product-reviews",
    "quote",
    "recommendation",
    "shipping",
  ]
}

run "registry_set" {
  command = plan

  assert {
    condition     = length(aws_ecr_repository.workload) == 17
    error_message = "The workload registry set must hold 17 repositories."
  }

  assert {
    condition     = toset(keys(aws_ecr_repository.workload)) == toset(var.expected_workload_repositories)
    error_message = "The workload registry set must be exactly the justified project-built inventory."
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.workload) == 17 && toset(keys(aws_ecr_lifecycle_policy.workload)) == toset(keys(aws_ecr_repository.workload))
    error_message = "Every workload repository, and nothing else, must carry a lifecycle policy."
  }

  assert {
    condition     = alltrue([for key, repository in aws_ecr_repository.workload : repository.name == "astroshop/${key}"])
    error_message = "Every workload repository must be named astroshop/<service>."
  }

  assert {
    condition     = alltrue([for repository in values(aws_ecr_repository.workload) : repository.image_tag_mutability == "IMMUTABLE"])
    error_message = "Every workload repository must have immutable tags."
  }

  assert {
    condition = alltrue([
      for repository in values(aws_ecr_repository.workload) :
      repository.force_delete == false &&
      repository.encryption_configuration[0].encryption_type == "AES256" &&
      repository.image_scanning_configuration[0].scan_on_push == false
    ])
    error_message = "Every workload repository must refuse force deletion, encrypt with AES256 and leave scanning to the pipeline."
  }

  assert {
    condition = alltrue([
      for key, policy in aws_ecr_lifecycle_policy.workload :
      policy.repository == "astroshop/${key}" &&
      length(jsondecode(policy.policy).rules) == 1 &&
      jsondecode(policy.policy).rules[0].selection.tagStatus == "tagged" &&
      jsondecode(policy.policy).rules[0].selection.countType == "imageCountMoreThan" &&
      jsondecode(policy.policy).rules[0].selection.countNumber == 10 &&
      jsondecode(policy.policy).rules[0].action.type == "expire"
    ])
    error_message = "Every lifecycle policy must keep exactly the newest 10 tagged images of its own repository."
  }

  assert {
    condition     = aws_ecr_repository.collector.name == "platform/opentelemetry-collector" && !contains([for repository in values(aws_ecr_repository.workload) : repository.name], aws_ecr_repository.collector.name)
    error_message = "The Collector mirror must stay a separately declared repository outside the workload set."
  }
}

# Repository ARNs exist only after apply; the mock gives each repository its own fake ARN.
# Targeted because the mocked certificate has no validation options for certificate.tf to read.
run "ci_push_scope" {
  command = apply

  plan_options {
    target = [
      aws_iam_role_policy.ci_checkout_ecr_push,
      aws_ecr_repository.collector,
    ]
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_checkout_ecr_push.policy).Statement[0].Resource) == 17 &&
      toset(jsondecode(aws_iam_role_policy.ci_checkout_ecr_push.policy).Statement[0].Resource) == toset([for repository in values(aws_ecr_repository.workload) : repository.arn])
    )
    error_message = "The push statement must cover exactly the 17 workload repositories."
  }

  assert {
    condition     = !contains(flatten([for statement in jsondecode(aws_iam_role_policy.ci_checkout_ecr_push.policy).Statement : statement.Resource]), aws_ecr_repository.collector.arn)
    error_message = "The CI push policy must not reach the Collector mirror."
  }

  assert {
    condition = (
      length(jsondecode(aws_iam_role_policy.ci_checkout_ecr_push.policy).Statement) == 2 &&
      jsondecode(aws_iam_role_policy.ci_checkout_ecr_push.policy).Statement[1].Action == "ecr:GetAuthorizationToken" &&
      jsondecode(aws_iam_role_policy.ci_checkout_ecr_push.policy).Statement[1].Resource == "*"
    )
    error_message = "The only unscoped statement must be the registry-level authorization token call."
  }
}
