locals {
  defaults = {
    enabled          = true
    namespace        = "strimzi-operator"
    kafka_version    = "4.3.0"
    metadata_version = "4.3-IV0"
    tier             = "nonprod"
    storage_class    = null
    node_selector    = {}
    tolerations      = []
    topics           = []
    users            = []
  }

  # Tier presets. "nonprod" (sandbox): one dual-role KafkaNodePool, a single
  # internal SCRAM listener, RF 1 everywhere — cheap and simple. "prod": split
  # controllers and brokers, an external listener, RF 3, CA lifecycle, metrics,
  # pod disruption budget and zone spreading. Any field can be overridden in
  # spec; overrides replace the whole value (no deep merge).
  tier_defaults = {
    nonprod = {
      topology = "dual-role"

      listeners = [
        { name = "scram", port = 9093, type = "internal", tls = true },
      ]

      kafka_config = {
        "auto.create.topics.enable"                = true
        "default.replication.factor"               = 1
        "min.insync.replicas"                      = 1
        "offsets.topic.replication.factor"         = 1
        "transaction.state.log.replication.factor" = 1
        "transaction.state.log.min.isr"            = 1
      }

      cluster_ca             = null
      kafka_exporter_enabled = false
      cruise_control_enabled = false
      pod_disruption_budget  = null
      scheduling             = null

      instances    = 1
      storage_size = "10Gi"
    }

    prod = {
      topology = "separate"

      listeners = [
        { name = "internal", port = 9092, type = "internal", tls = true },
        { name = "external", port = 9096, type = "loadbalancer", tls = true },
      ]

      kafka_config = {
        "auto.create.topics.enable"                = true
        "default.replication.factor"               = 3
        "min.insync.replicas"                      = 2
        "offsets.topic.replication.factor"         = 3
        "transaction.state.log.replication.factor" = 3
        "transaction.state.log.min.isr"            = 2
      }

      cluster_ca = {
        validity_days                 = 3650
        renewal_days                  = 30
        certificate_expiration_policy = "renew-certificate"
      }

      kafka_exporter_enabled = true
      cruise_control_enabled = false
      pod_disruption_budget  = { max_unavailable = 1 }

      scheduling = {
        topology_spread_constraints = [
          { max_skew = 1, topology_key = "topology.kubernetes.io/zone", when_unsatisfiable = "ScheduleAnyway" },
          { max_skew = 1, topology_key = "kubernetes.io/hostname", when_unsatisfiable = "DoNotSchedule" },
        ]
      }

      controllers = {
        replicas     = 3
        storage_size = "5Gi"
        jvm_options  = { "-Xms" = "512m", "-Xmx" = "512m" }
        resources = {
          requests = { cpu = "250m", memory = "1Gi" }
          limits   = { cpu = "1", memory = "2Gi" }
        }
      }

      brokers = {
        replicas     = 3
        storage_size = "50Gi"
        jvm_options  = { "-Xms" = "2g", "-Xmx" = "2g" }
        resources = {
          requests = { cpu = "500m", memory = "3Gi" }
          limits   = { cpu = "2", memory = "5Gi" }
        }
      }
    }
  }

  spec = merge(local.defaults, module.context.spec)
  config = merge(
    local.defaults,
    lookup(local.tier_defaults, local.spec.tier, local.tier_defaults.nonprod),
    module.context.spec,
  )

  # One unit = one Kafka cluster: strimzi-kafka-cluster.<instance>.yaml
  name               = coalesce(local.instance, "missing")
  kafka_cluster_name = "kafka-${local.name}"
  bootstrap          = "${local.kafka_cluster_name}-kafka-bootstrap.${local.config.namespace}.svc.cluster.local"

  # KafkaUser/KafkaTopic objects are prefixed with the cluster name so two
  # clusters in one namespace never collide; the topic keeps its real name.
  users = {
    for u in local.config.users : u.name => {
      k8s_name = "${local.kafka_cluster_name}-${replace(u.name, "_", "-")}"
      acls     = try(u.acls, [])
    }
  }
  topics = [
    for t in local.config.topics : merge(t, {
      resourceName = "${local.kafka_cluster_name}-${lower(replace(coalesce(try(t.resourceName, null), t.name), "_", "-"))}"
    })
  ]
}
