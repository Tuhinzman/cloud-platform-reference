# Read at plan and apply, never stored in state or a plan file.
ephemeral "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
}

resource "aws_db_instance" "datastore" {
  identifier = "cloud-platform-reference-dev-datastore"

  # The region default for a new instance is a newer major; the workload targets 17.
  engine         = "postgres"
  engine_version = "17.11"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "otel"
  username = "otel_admin"

  # Bump the version together with every new master value; the value alone is never sent.
  password_wo         = ephemeral.aws_secretsmanager_secret_version.master.secret_string
  password_wo_version = 1

  db_subnet_group_name   = aws_db_subnet_group.datastore.name
  vpc_security_group_ids = [aws_security_group.datastore.id]
  publicly_accessible    = false
  multi_az               = false

  # The PostgreSQL 17 default group sets rds.force_ssl = 1.
  parameter_group_name = "default.postgres17"
  ca_cert_identifier   = "rds-ca-rsa2048-g1"

  backup_retention_period = 7
  backup_window           = "04:00-04:30"
  maintenance_window      = "sun:05:00-sun:05:30"
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade = false
  # Only settable at creation in this provider version.
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"
  apply_immediately        = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "cloud-platform-reference-dev-datastore-final"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "endpoint" {
  name  = "cloud-platform-reference-dev-datastore-endpoint"
  type  = "String"
  tier  = "Standard"
  value = aws_db_instance.datastore.address
}
