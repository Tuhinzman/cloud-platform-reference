# The bundled Terraform ruleset checks language and style. It is declared
# explicitly rather than left to the default so the preset in force is visible
# to a reviewer.
#
# No provider ruleset is configured. The AWS ruleset ships as a separate plugin
# that has to be installed before any run, and no incremental value over the
# bundled rules was demonstrated for the five resources in this root. Adding it
# back is a deliberate change rather than a default.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
