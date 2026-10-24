# ── Management cluster: generate credentials on first apply ──────────────────

resource "random_password" "admin" {
  count            = local.is_management ? 1 : 0
  length           = 20
  special          = true
  override_special = "!@#%^&*()-_=+[]{}|"
}

resource "random_password" "token_signing_key" {
  count   = local.is_management ? 1 : 0
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "admin" {
  count                   = local.is_management ? 1 : 0
  name                    = "${local.secret_path}/admin"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "admin" {
  count     = local.is_management ? 1 : 0
  secret_id = aws_secretsmanager_secret.admin[0].id
  secret_string = jsonencode({
    password                        = random_password.admin[0].result
    ADMIN_ACCOUNT_PASSWORD_HASH     = bcrypt(random_password.admin[0].result)
    ADMIN_ACCOUNT_TOKEN_SIGNING_KEY = random_password.token_signing_key[0].result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ── Credential locals consumed by main.tf ────────────────────────────────────

locals {
  kargo_admin_password_hash = (local.is_management
    ? jsondecode(aws_secretsmanager_secret_version.admin[0].secret_string)["ADMIN_ACCOUNT_PASSWORD_HASH"]
  : "")
  kargo_token_signing_key = (local.is_management
    ? jsondecode(aws_secretsmanager_secret_version.admin[0].secret_string)["ADMIN_ACCOUNT_TOKEN_SIGNING_KEY"]
  : "")
}
