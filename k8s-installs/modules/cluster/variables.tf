variable "state" {
  description = "S3 backend settings of the account (module.context.state)."
  type = object({
    bucket     = string
    region     = string
    kms_key_id = optional(string)
  })
}

variable "env_id" {
  description = "infrastructure environment (module.context.env_id)."
  type        = string
}

variable "region" {
  description = "Region of the cluster's core-platform unit."
  type        = string
}

variable "cluster" {
  description = "Key of the cluster in core-platform's clusters output, e.g. \"1\"."
  type        = string
}

variable "dns_zone" {
  description = "Key of the cluster's zone in the dns unit's zones output."
  type        = string
  default     = "zone-1"
}
