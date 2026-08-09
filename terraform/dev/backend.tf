terraform {
  # Partial configuration. The state bucket name is operator-specific and never
  # committed, so it arrives through -backend-config=backend.hcl. That is the
  # bucket the bootstrap root created. This root creates no bucket of its own.
  #
  # The key differs from the other roots' keys. ADR-0003 isolates state at the
  # configuration-root level, so a mistake here cannot reach the state of the
  # backend or of the evidence destination.
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
