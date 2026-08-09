terraform {
  # Partial configuration. The state bucket name is operator-specific and never
  # committed, so it arrives through -backend-config=backend.hcl. That is the
  # bucket the bootstrap root created, not the bucket this root creates.
  #
  # The key differs from the bootstrap root's key. ADR-0003 isolates state at
  # the configuration-root level, so a mistake in one root cannot reach the
  # other's state object.
  backend "s3" {
    key          = "foundation/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
