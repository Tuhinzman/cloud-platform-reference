variable "evidence_bucket_name" {
  description = "Name of the durable raw-evidence bucket this root creates. S3 bucket names are globally unique, so this value belongs to the operator and is never committed. It is not the Terraform state bucket."
  type        = string

  validation {
    # Periods are legal in a bucket name but break the wildcard certificate on
    # virtual-hosted-style HTTPS requests, and the bucket policy in main.tf
    # makes TLS mandatory, so they are excluded here rather than left to fail
    # later. The rest of the pattern is the S3 naming rule.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.evidence_bucket_name))
    error_message = "evidence_bucket_name must be 3 to 63 characters using lowercase letters, digits and hyphens only, starting and ending with a letter or digit."
  }
}

variable "gitlab_project_path" {
  description = "Full path of the GitLab project whose main-branch CI may assume the push role, as group/project without the scheme or host. It is the project coordinate the OIDC sub claim carries, so it is supplied at execution time and never committed."
  type        = string

  validation {
    # A path, not a URL. A value carrying a scheme or a host would produce a sub
    # condition that never matches, and the role would silently trust nothing.
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*(/[a-zA-Z0-9][a-zA-Z0-9._-]*)+$", var.gitlab_project_path))
    error_message = "gitlab_project_path must be the group/project path without a scheme or host, for example group/project or group/subgroup/project."
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
