variable "operator_cidr" {
  description = "The single public IPv4 CIDR permitted to reach the EKS public API endpoint. It is the operator's own address, it changes with the network they work from, and it is never committed. Supplied at execution time."
  type        = string

  validation {
    # cidrhost rejects what the pattern alone accepts, such as 300.1.1.1/32.
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([1-9]|[12][0-9]|3[0-2])$", var.operator_cidr)) && can(cidrhost(var.operator_cidr, 0))
    error_message = "operator_cidr must be one IPv4 CIDR with a prefix between /1 and /32. A /0 is rejected because it would reopen the public endpoint to the whole internet."
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

variable "alerting_campaign_enabled" {
  description = "Creates the REQ-015 alerting campaign: the topic, the publish role and policy, and the Pod Identity association. Off by default so an ordinary window apply does not create it."
  type        = bool
  default     = false
}

variable "alerting_email_subscription_enabled" {
  description = "Creates the REQ-015 alerting email subscription when true and alerting_campaign_enabled is true. Off by default so the root plans and validates without the private endpoint; the operator enables it for the alerting window."
  type        = bool
  default     = false
}

variable "alerting_email_endpoint" {
  description = "Owner-controlled email address that subscribes to the REQ-015 alerting topic. A private execution input: never committed, never written to evidence, redacted in plan and apply output. Required only when alerting_campaign_enabled and alerting_email_subscription_enabled are both true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.alerting_email_endpoint == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alerting_email_endpoint))
    error_message = "alerting_email_endpoint must be one email address."
  }
}
