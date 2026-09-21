variable "evidence_bucket_name" {
  description = "Name of the durable raw-evidence bucket this root creates. S3 bucket names are globally unique, so this value belongs to the operator and is never committed. It is not the Terraform state bucket."
  type        = string

  validation {
    # Periods are legal in S3 names but break TLS on virtual-hosted-style requests.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.evidence_bucket_name))
    error_message = "evidence_bucket_name must be 3 to 63 characters using lowercase letters, digits and hyphens only, starting and ending with a letter or digit."
  }
}

variable "gitlab_project_id" {
  description = "Immutable numeric ID GitLab assigns to the project whose main-branch CI may assume the push role. It is the project coordinate the OIDC sub claim carries, so it is supplied at execution time and never committed."
  type        = number

  validation {
    # The sub claim is matched exactly, so a fractional ID would match nothing.
    condition     = var.gitlab_project_id > 0 && floor(var.gitlab_project_id) == var.gitlab_project_id
    error_message = "gitlab_project_id must be the positive whole number GitLab assigns to the project, digits only."
  }
}

variable "allowed_account_id" {
  description = "AWS account ID this configuration is permitted to act on. The provider refuses every other account, so a wrong credential fails before any resource is created. Supplied at execution time and never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.allowed_account_id))
    error_message = "allowed_account_id must be the 12-digit AWS account ID, digits only."
  }
}

variable "public_domain" {
  description = "Registered apex domain whose public hosted zone this root creates. An owner-private execution input under ADR-0018, supplied at execution time and never committed."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+([a-z]{2,63}|xn--[a-z0-9-]{1,59})$", var.public_domain))
    error_message = "public_domain must be a lowercase domain name such as example.com, without a trailing dot."
  }
}
