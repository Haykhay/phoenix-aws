# Identical in every resource-set root except `resource_set` and `network`.
# module.context reads the unit's YAML; the locals bridge its outputs to the
# names the module bodies use.

variable "config_file" {
  description = "Path to this unit's YAML: environments/<tier>/<env_id>/<scope>/<resource-set>.yaml."
  type        = string
}

variable "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR). Seed for CreatedBy, frozen at creation."
  type        = string
  default     = "unknown"
}

module "context" {
  source = "../context"

  config_file   = var.config_file
  resource_set  = "data-elasticache"
  network       = true
  pipeline_user = var.pipeline_user
}

locals {
  environment      = module.context.env_id
  scope            = module.context.scope
  region           = module.context.region
  account_id       = module.context.account_id
  organisation     = module.context.organisation
  base_name_prefix = module.context.name_prefix
  core_network     = module.context.network
  core_networks    = module.context.networks
}
