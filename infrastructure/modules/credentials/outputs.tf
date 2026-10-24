output "passwords" {
  description = "Generated password per credential key."
  value       = { for name, password in random_password.this : name => password.result }
  sensitive   = true
}

output "credentials" {
  description = <<-EOT
    Username and password per credential key, for consumers that build their
    own secret payload rather than using `publish`.
  EOT
  value = {
    for name, password in random_password.this : name => {
      username = var.credentials[name].username
      password = password.result
    }
  }
  sensitive = true
}

output "secret_arns" {
  description = "ARN of the published secret, per credential key. Empty for credentials that publish nothing."
  value       = { for name, secret in aws_secretsmanager_secret.this : name => secret.arn }
}

output "secret_names" {
  description = <<-EOT
    Name of the published secret, per credential key. This is the
    discovery path, and is what a Layer 3 consumer looks up.
  EOT
  value       = { for name, secret in aws_secretsmanager_secret.this : name => secret.name }
}
