resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.instance != null
      error_message = "strimzi-kafka-cluster is per cluster: name the file strimzi-kafka-cluster.<name>.yaml."
    }
  }
}

# SCRAM passwords at <organisation>/<env_id>/kafka/in-cluster/<instance>/<user>,
# where external-secrets may read them.
module "credentials" {
  source = "../../../infrastructure/modules/credentials"

  organisation = local.organisation

  credentials = local.config.enabled ? {
    for name, u in local.users : "user-${name}" => { policy = "generic", username = u.k8s_name }
  } : {}

  publish = local.config.enabled ? {
    for name, u in local.users : "user-${name}" => {
      environment = local.environment
      service     = "kafka"
      binding     = "in-cluster"
      instance    = "${local.name}/${name}"
      description = "SCRAM user ${u.k8s_name} of ${local.kafka_cluster_name}"
      payload     = { bootstrap = "${local.bootstrap}:9093", mechanism = "SCRAM-SHA-512", engine = "kafka" }
    }
  } : {}
}

resource "helm_release" "cluster" {
  count            = local.config.enabled ? 1 : 0
  name             = local.kafka_cluster_name
  chart            = "${path.module}/manifests/cluster"
  namespace        = local.config.namespace
  create_namespace = true
  wait             = true
  wait_for_jobs    = true
  timeout          = 600
  atomic           = true
  cleanup_on_fail  = true

  values = [yamlencode({
    clusterName         = local.kafka_cluster_name
    kafkaVersion        = local.config.kafka_version
    metadataVersion     = local.config.metadata_version
    topology            = local.config.topology
    listeners           = local.config.listeners
    kafkaConfig         = local.config.kafka_config
    clusterCa           = local.config.cluster_ca
    kafkaExporter       = { enabled = local.config.kafka_exporter_enabled }
    cruiseControl       = { enabled = local.config.cruise_control_enabled }
    podDisruptionBudget = local.config.pod_disruption_budget
    storageClass        = local.config.storage_class
    nodeSelector        = local.config.node_selector
    tolerations         = local.config.tolerations
    scheduling          = local.config.scheduling

    # "dual-role" (nonprod) uses instances/storageSize; "separate" (prod) uses controllers/brokers.
    instances   = try(local.config.instances, null)
    storageSize = try(local.config.storage_size, null)
    controllers = try(local.config.controllers, null)
    brokers     = try(local.config.brokers, null)
  })]

  depends_on = [terraform_data.validation]
}

resource "helm_release" "topics" {
  count            = local.config.enabled && length(local.topics) > 0 ? 1 : 0
  name             = "${local.kafka_cluster_name}-topics"
  chart            = "${path.module}/manifests/topics"
  namespace        = local.config.namespace
  create_namespace = true
  wait             = true
  timeout          = 300
  atomic           = true
  cleanup_on_fail  = true

  values = [yamlencode({ clusterName = local.kafka_cluster_name, topics = local.topics })]

  depends_on = [helm_release.cluster]
}

resource "helm_release" "users" {
  count            = local.config.enabled && length(local.users) > 0 ? 1 : 0
  name             = "${local.kafka_cluster_name}-users"
  chart            = "${path.module}/manifests/users"
  namespace        = local.config.namespace
  create_namespace = true
  wait             = true
  timeout          = 300
  atomic           = true
  cleanup_on_fail  = true

  values = [yamlencode({
    clusterName = local.kafka_cluster_name
    users = [
      for name, u in local.users : {
        name         = u.k8s_name
        smSecretName = module.credentials.secret_names["user-${name}"]
        acls         = u.acls
      }
    ]
  })]

  depends_on = [helm_release.cluster, module.credentials]
}
