variable "operator_cidr" {
  description = "The single public IPv4 CIDR permitted to reach the EKS public API endpoint. It is the operator's own address, it changes with the network they work from, and it is never committed. Supplied at execution time."
  type        = string

  validation {
    # A /0 is rejected on purpose. The reason this variable exists is that the
    # AWS default of 0.0.0.0/0 leaves authentication as the only barrier in
    # front of the API server, and a /0 supplied here would restore exactly
    # that. cidrhost rejects an address the shape pattern alone would accept,
    # such as 300.1.1.1/32.
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
