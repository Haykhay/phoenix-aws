output "cluster_names" {
  description = "Keys of the replication groups."
  value       = keys(local.elasticache_clusters)
}

output "elasticache" {
  description = "ElastiCache connection info"
  value = {
    for name, cluster in module.elasticache : name => {
      primary_endpoint = cluster.replication_group_primary_endpoint_address
      reader_endpoint  = cluster.replication_group_reader_endpoint_address
      port             = cluster.replication_group_port
    }
  }
  sensitive = true
}

output "secret_arns" {
  description = "Connection secret ARN, by replication group."
  value = {
    for name, secret in module.elasticache_secrets_manager : name => secret.secret_arn
  }
}

output "kms_key_arns" {
  description = "KMS key ARN, by replication group."
  value = {
    for name, key in aws_kms_key.elasticache : name => key.arn
  }
}

output "security_group_ids" {
  description = "Security group ID, by replication group."
  value = {
    for name, sg in aws_security_group.elasticache : name => sg.id
  }
}

output "resource_summary" {
  value = {
    environment   = local.environment
    region        = local.region
    resource_set  = "data-elasticache"
    cluster_names = keys(local.elasticache_clusters)
  }
}
