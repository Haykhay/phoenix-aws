output "cluster" {
  description = "The Kafka cluster and where its users' credentials are published."
  value = local.config.enabled ? {
    name         = local.kafka_cluster_name
    namespace    = local.config.namespace
    bootstrap    = local.bootstrap
    user_secrets = { for name, u in local.users : name => module.credentials.secret_names["user-${name}"] }
  } : null
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    cluster      = local.cluster_key
    resource_set = "strimzi-kafka-cluster"
    instance     = local.instance
    tier         = local.config.tier
  }
}
