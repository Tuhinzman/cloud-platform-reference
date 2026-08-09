# Both Terraform roots declare the bundled Terraform ruleset explicitly and both
# use preset "recommended", so the lint configuration is visible to a reviewer
# and deterministic across the repository rather than inferred per directory.
#
# No provider ruleset is configured. The AWS ruleset ships as a separate plugin
# that has to be installed before any run, and no incremental value over the
# bundled rules has been demonstrated for these roots.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
