variable "operator_cidr" {
  description = "The single public IPv4 CIDR permitted to reach the EKS public API endpoint. It is the operator's own address, it changes with the network they work from, and it is never committed. Supplied at execution time."
  type        = string
  # Keeps the address out of plan and apply text. State and JSON output still carry it, so
  # captured evidence is redacted as well.
  sensitive = true

  validation {
    # The cidrhost round trip rejects out-of-range octets and non-canonical forms such as 010.0.0.1/32.
    condition = (
      can(regex("^[0-9.]+/32$", var.operator_cidr)) &&
      try(cidrhost(var.operator_cidr, 0) == trimsuffix(var.operator_cidr, "/32"), false)
    )
    error_message = "operator_cidr must be exactly one IPv4 host address as a /32 in canonical dotted-decimal form, for example 203.0.113.10/32."
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

variable "worker_capacity_enabled" {
  description = "Creates the worker capacity and what exists only to serve it: the node group with its role, policy attachments and launch template, the NAT path, and the External Secrets Pod Identity association. False gives the control-plane-only observation shape, the cluster and its four pinned add-ons with no node, so no add-on container can run."
  type        = bool
  default     = true
}

variable "node_measurement_only" {
  description = "With worker_capacity_enabled, creates the node group with no add-on that schedules a pod: no vpc-cni, kube-proxy or Pod Identity agent add-on, no External Secrets Pod Identity association, and CoreDNS at zero replicas. Whether nodes join, and that no pod runs, are measured in the window, never assumed."
  type        = bool
  default     = false

  validation {
    condition     = !var.node_measurement_only || var.worker_capacity_enabled
    error_message = "node_measurement_only needs worker_capacity_enabled: it measures the node group."
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

variable "public_entry_enabled" {
  description = "Creates the Pod Identity role, inline policy and association of each public-entry controller under ADR-0018. Off by default, so an ordinary window apply, node measurement and the retained baseline create none of them. Needs worker capacity without node measurement, because the controllers run as pods."
  type        = bool
  default     = false

  validation {
    condition     = !var.public_entry_enabled || (var.worker_capacity_enabled && !var.node_measurement_only)
    error_message = "public_entry_enabled needs worker_capacity_enabled without node_measurement_only: the controllers run as pods."
  }
}

variable "public_hosted_zone_id" {
  description = "ID of the public hosted zone the foundation root created for the apex domain. The record controller can change records in this zone and in no other. An owner-private execution input, never committed. Required only when public_entry_enabled is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.public_hosted_zone_id == null ? !var.public_entry_enabled : can(regex("^Z[0-9A-Z]{8,32}$", var.public_hosted_zone_id))
    error_message = "public_hosted_zone_id must be a Route 53 hosted zone ID such as Z0000000000EXAMPLE, without a path prefix, and is required when public_entry_enabled is true."
  }
}

variable "public_domain" {
  description = "Registered apex domain of that zone, the foundation root's public_domain. The environment is reached at dev beneath it. An owner-private execution input under ADR-0018, never committed. Required only when public_entry_enabled is true."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.public_domain == null ? !var.public_entry_enabled : can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+([a-z]{2,63}|xn--[a-z0-9-]{1,59})$", var.public_domain))
    error_message = "public_domain must be a lowercase domain name such as example.com, without a trailing dot, and is required when public_entry_enabled is true."
  }
}
