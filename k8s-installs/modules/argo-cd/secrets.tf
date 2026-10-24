resource "random_password" "admin" {
  count            = local.config.enabled ? 1 : 0
  length           = 20
  special          = true
  override_special = "!@#%^&*()-_=+[]{}|"
}

resource "tls_private_key" "repo" {
  count     = local.config.enabled ? 1 : 0
  algorithm = "ED25519"
}

resource "aws_secretsmanager_secret" "admin" {
  count                   = local.config.enabled ? 1 : 0
  name                    = "${local.secret_path}/admin"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "admin" {
  count     = local.config.enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.admin[0].id
  secret_string = jsonencode({
    password      = random_password.admin[0].result
    password_hash = bcrypt(random_password.admin[0].result)
  })

  lifecycle {
    # bcrypt() uses a random salt so the hash differs on every plan.
    # Freeze the value written on first apply; it never needs to change
    # unless the password is deliberately rotated (taint the resource).
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "repo_ssh" {
  count                   = local.config.enabled ? 1 : 0
  name                    = "${local.secret_path}/repo-ssh-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "repo_ssh" {
  count         = local.config.enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.repo_ssh[0].id
  secret_string = tls_private_key.repo[0].private_key_openssh
}

locals {
  argocd_admin_password_hash  = local.config.enabled ? jsondecode(aws_secretsmanager_secret_version.admin[0].secret_string)["password_hash"] : ""
  argocd_repo_ssh_private_key = local.config.enabled ? tls_private_key.repo[0].private_key_openssh : ""
}
