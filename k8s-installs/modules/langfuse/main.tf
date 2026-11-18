# Langfuse: LLM tracing and evaluation for the cluster's model workloads.
# Bundled Postgres, ClickHouse and Redis (sandbox-sized); blob storage in the
# group's long-lived observability bucket.
data "terraform_remote_state" "observability" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${module.context.group}-${local.config.observability_environment}/${local.region}/observability/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || can(local.observability.bucket_name)
      error_message = "No observability state for ${module.context.group}-${local.config.observability_environment}/${local.region}: apply infrastructure's observability unit for the group first."
    }
    precondition {
      condition     = !local.config.enabled || local.dns != null
      error_message = "langfuse's UI route needs the cluster's DNS zone from infrastructure's dns unit."
    }
  }
}

# Generated once, kept in state (encrypted backend); rotating one means
# tainting it.
resource "random_password" "salt" {
  count   = local.config.enabled ? 1 : 0
  length  = 32
  special = false
}

resource "random_id" "encryption_key" {
  count       = local.config.enabled ? 1 : 0
  byte_length = 32 # 64 hex characters, as Langfuse requires
}

resource "random_password" "nextauth" {
  count   = local.config.enabled ? 1 : 0
  length  = 32
  special = false
}

resource "random_password" "db" {
  for_each = local.config.enabled ? toset(["postgresql", "clickhouse", "redis"]) : toset([])
  length   = 30
  special  = false
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "langfuse"
  repository       = "https://langfuse.github.io/langfuse-k8s"
  chart            = "langfuse"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true
  timeout          = 900

  values = [yamlencode({
    langfuse = {
      nextauth       = { url = "https://${local.hostname}" }
      serviceAccount = { create = true, name = local.service_account }
    }
    s3 = {
      deploy          = false
      storageProvider = "s3"
      bucket          = local.bucket
      region          = local.region
      # Real S3: virtual-hosted addressing (path style is for S3-compatible stores).
      forcePathStyle = false
      # Credentials come from Pod Identity (langfuse/langfuse), not keys.
      eventUpload = { prefix = "${local.blob_prefix}events/" }
      mediaUpload = { prefix = "${local.blob_prefix}media/" }
      batchExport = { prefix = "${local.blob_prefix}exports/" }
    }
  })]

  set_sensitive = [
    { name = "langfuse.salt.value", value = random_password.salt[0].result },
    { name = "langfuse.encryptionKey.value", value = random_id.encryption_key[0].hex },
    { name = "langfuse.nextauth.secret.value", value = random_password.nextauth[0].result },
    { name = "postgresql.auth.password", value = random_password.db["postgresql"].result },
    { name = "clickhouse.auth.password", value = random_password.db["clickhouse"].result },
    { name = "redis.auth.password", value = random_password.db["redis"].result },
  ]

  depends_on = [terraform_data.validation]
}

resource "helm_release" "route" {
  count     = local.config.enabled ? 1 : 0
  name      = "langfuse-route"
  chart     = "${path.module}/manifests/route"
  namespace = local.namespace

  values = [yamlencode({
    name     = "langfuse"
    hostname = local.hostname
    gateway  = { name = "istio-internal", namespace = "istio-system" }
    service  = { name = "langfuse-web", port = 3000 }
  })]

  depends_on = [helm_release.this]
}
