variable "config_file" {
  description = "Path to the unit's YAML: environments/<tier>/<env_id>/<scope>/<resource-set>.yaml."
  type        = string
}

variable "resource_set" {
  description = "Resource set of the calling root, e.g. core-platform. Used for the state key and the ResourceSet tag."
  type        = string
}

variable "network" {
  description = "Look up the selected VPC from core-network's state. True for VPC-bound resource sets."
  type        = bool
  default     = false
}

variable "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR). Seed for CreatedBy, which roots freeze at creation."
  type        = string
  default     = "unknown"
}
