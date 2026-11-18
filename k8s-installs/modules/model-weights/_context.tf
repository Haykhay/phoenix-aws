variable "config_file" {
  description = "Path to this unit's YAML (k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/<component>[.<instance>].yaml)."
  type        = string
}

variable "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR)."
  type        = string
  default     = "unknown"
}

module "context" {
  source = "../../../infrastructure/modules/context"

  config_file   = var.config_file
  resource_set  = "model-weights"
  pipeline_user = var.pipeline_user
}

module "cluster" {
  source = "../cluster"

  state    = module.context.state
  env_id   = module.context.env_id
  region   = module.context.region
  cluster  = module.context.config.cluster
  dns_zone = try(module.context.config.dns_zone, "zone-1")
}

locals {
  environment  = module.context.env_id
  region       = module.context.region
  account_id   = module.context.account_id
  organisation = module.context.organisation
  cluster_key  = tostring(module.context.config.cluster)
  # <component>.<instance>.yaml -> instance; singletons have none.
  instance = try(regex("^[^.]+\\.(.+)\\.yaml$", basename(var.config_file))[0], null)
  # Cluster- and instance-unique: research-sandbox-jdoe-euw1-1[-llama-3-8b]
  name_prefix  = join("-", compact([module.context.name_prefix, local.cluster_key, local.instance]))
  cluster_name = module.cluster.cluster_name
}
