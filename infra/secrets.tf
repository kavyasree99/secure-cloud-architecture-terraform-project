resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#$%^&*()-_=+"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name}-db-credentials"
  description             = "Master credentials for the RDS instance, consumed by the ECS task definition"
  recovery_window_in_days = 0

  tags = {
    Name = "${local.name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}
