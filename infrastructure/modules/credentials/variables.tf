variable "organisation" {
  description = "Organisation name; the first segment of every published secret name."
  type        = string
}

variable "credentials" {
  description = <<-EOT
    Credentials to generate, keyed by a stable name. Renaming a key regenerates
    that password, so treat the keys as identifiers rather than labels.

    Every credential names a policy. There is no per-credential override of the
    generated character set or length: a password either meets the platform
    standard or the standard changes for everyone on that policy.

  EOT

  type = map(object({
    policy   = string
    username = optional(string)

    # Changing any value here regenerates this one password without changing
    # policy — for a suspected leak, or a scheduled rotation.
    keepers = optional(map(string))
  }))

  validation {
    condition = alltrue([
      for name, credential in var.credentials : contains(
        [
          "rds_master",
          "rds_app",
          "elasticache_auth",
          "msk_scram",
          "postgres_incluster",
          "redis_incluster",
          "generic",
        ],
        credential.policy,
      )
    ])
    error_message = "policy must be one of: rds_master, rds_app, elasticache_auth, msk_scram, postgres_incluster, redis_incluster, generic. Adding one is an append-only change to the module."
  }
}

variable "publish" {
  description = <<-EOT
    Optional Secrets Manager publication, per credential key. A key absent from
    this map generates a password and publishes nothing — which is how the
    existing data-rds and data-elasticache secrets stay where they are.

    Secrets land at the secret path convention:

      <organisation>/<environment>/<service>/<binding>[/<instance>]

    instance is only needed when one environment holds several of the same
    service; omit it for the singleton case the ADR describes.

    MSK SASL/SCRAM is the exception: AWS requires those secret names to begin
    with "AmazonMSK_", so a msk_scram credential is published as
    AmazonMSK_<organisation>_<environment>_<service>_<binding>[_<instance>] instead.

    payload is merged into the stored JSON alongside username/password, and is
    where connection details (endpoint, port, engine) belong. Passing a value
    that depends on the backing resource is fine — the password is generated
    before the resource exists, the secret is written after.
  EOT

  type = map(object({
    environment = string
    service     = string
    binding     = string
    instance    = optional(string)

    payload     = optional(map(string), {})
    kms_key_arn = optional(string)
    description = optional(string)

    # 0 deletes immediately instead of soft-deleting for 30 days. Ephemeral
    # deployments need this or the next create collides with the scheduled
    # deletion of the old secret.
    recovery_window_in_days = optional(number, 0)
    tags                    = optional(map(string), {})
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, entry in var.publish : contains(["managed", "in-cluster"], entry.binding)
    ])
    error_message = "binding must be either \"managed\" or \"in-cluster\"."
  }
}
