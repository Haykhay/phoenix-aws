output "instance_names" {
  value = keys(local.instances)
}

output "rds" {
  description = "RDS connection info"
  value = {
    for name, db in module.rds : name => {
      host     = db.db_instance_address
      port     = db.db_instance_port
      database = db.db_instance_name
      username = db.db_instance_username
      password = module.credentials.passwords[name]
    }
  }
  sensitive = true
}

output "secret_arns" {
  value = {
    for name, secret in module.rds_secrets_manager : name => secret.secret_arn
  }
}

output "kms_key_arns" {
  value = {
    for name, key in aws_kms_key.rds : name => key.arn
  }
}

output "security_group_ids" {
  value = {
    for name, sg in aws_security_group.rds : name => sg.id
  }
}

output "resource_summary" {
  value = {
    environment    = local.environment
    region         = local.region
    resource_set   = "data-rds"
    instance_names = keys(local.instances)
  }
}
