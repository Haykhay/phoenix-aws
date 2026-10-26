output "clusters" {
  description = "Every MSK cluster in this resource set, keyed by its config name."
  value = {
    for name, cluster in local.clusters : name => {
      name                       = cluster.name_prefix
      arn                        = module.msk[name].arn
      bootstrap_brokers_sasl_iam = module.msk[name].bootstrap_brokers_sasl_iam
      secret_arn                 = aws_secretsmanager_secret.msk[name].arn
      kms_key_arn                = aws_kms_key.msk[name].arn
      security_group_id          = aws_security_group.msk[name].id
      vpc                        = cluster.vpc

      # Secret name per SCRAM username, for consumers that authenticate with
      # SASL/SCRAM rather than IAM. Empty for clusters with no scram_users.
      scram_secrets = {
        for key, credential in local.scram_credentials :
        credential.username => module.scram_credentials.secret_names[key]
        if credential.cluster_key == name
      }
    }
  }
}

output "default_cluster_name" {
  description = "Config key of the cluster the flat outputs resolve to."
  value       = local.config.enabled ? local.default_cluster_name : null
}

output "cluster_names" {
  description = "Keys of the MSK clusters."
  value       = keys(local.clusters)
}

# --- Deprecated single-cluster shims ---

output "bootstrap_brokers_sasl_iam" {
  description = "Default cluster: IAM-auth bootstrap brokers."
  value       = local.config.enabled ? module.msk[local.default_cluster_name].bootstrap_brokers_sasl_iam : null
}

output "secret_arn" {
  description = "ARN of the connection-info secret (bootstrap brokers)"
  value       = local.config.enabled ? aws_secretsmanager_secret.msk[local.default_cluster_name].arn : null
}

output "kms_key_arn" {
  description = "Default cluster: KMS key ARN."
  value       = local.config.enabled ? aws_kms_key.msk[local.default_cluster_name].arn : null
}

output "security_group_id" {
  description = "Default cluster: security group ID."
  value       = local.config.enabled ? aws_security_group.msk[local.default_cluster_name].id : null
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    resource_set = "data-msk"
    clusters     = keys(local.clusters)
    default      = local.config.enabled ? local.default_cluster_name : null
  }
}
