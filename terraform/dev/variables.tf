variable "allowed_account_id" {
  description = "AWS account ID this configuration is permitted to act on. The provider refuses every other account, so a wrong credential fails before any resource is created. Supplied at execution time and never committed."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.allowed_account_id))
    error_message = "allowed_account_id must be the 12-digit AWS account ID, digits only."
  }
}
