# Identical in every networking unit except `resource_set`. module.context
# reads the unit's YAML; the locals bridge its outputs to the names the module
# bodies use.

variable "config_file" {
  description = "Path to this unit's YAML: networking/environments/<scope>/<unit>[.<instance>].yaml."
  type        = string
}

variable "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR). Seed for CreatedBy, frozen at creation."
  type        = string
  default     = "unknown"
}

module "context" {
  source = "../../../infrastructure/modules/context"

  config_file   = var.config_file
  resource_set  = "region"
  pipeline_user = var.pipeline_user
}

locals {
  region      = module.context.region
  account_id  = module.context.account_id
  name_prefix = module.context.name_prefix
  spec        = module.context.spec
  network     = module.context.platform_network
}
