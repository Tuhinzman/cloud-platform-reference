# No _version resource: values are placed out of band, so no password enters state
# or a plan. The master value must exist before database.tf is planned.
resource "aws_secretsmanager_secret" "master" {
  name                    = "cloud-platform-reference-dev-datastore-master"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "cloud-platform-reference-dev-datastore-app"
  recovery_window_in_days = 7
}
