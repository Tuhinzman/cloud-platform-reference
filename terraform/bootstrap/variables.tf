variable "state_bucket_name" {
  description = "Name of the Terraform remote state bucket. S3 bucket names are globally unique, so this value belongs to the operator and is never committed. Supply it at execution time, and use the same value for the -backend-config bucket argument."
  type        = string

  validation {
    # Periods are legal in S3 names but break TLS on virtual-hosted-style requests.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be 3 to 63 characters using lowercase letters, digits and hyphens only, starting and ending with a letter or digit."
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
