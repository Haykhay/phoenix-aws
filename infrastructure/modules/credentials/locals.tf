locals {
  # policies is APPEND-ONLY. Once a key is in use, do not change its values —
  # random_password regenerates whenever any argument changes, so editing a
  # policy in place rotates every password using it, everywhere, on the next
  # apply. To change a policy, add a new key (`rds_master_v2`) and move
  # consumers onto it one at a time. That bump is the rotation trigger, and it
  # is visible in the environment JSON and in review.
  #
  # No punctuation, length instead. Every escaping problem the per-module
  # generators used to work around — RDS rejecting / @ " and space, ElastiCache
  # permitting only eight specials, MSK storing credentials as JSON, in-cluster
  # backings pasting the password into a connection URI — is a property of the
  # punctuation, not of the password. Removing it kills all of them at once,
  # and 30 alphanumeric characters (~10^53) is a far larger search space than
  # 20 mixed ones (~10^38).
  #
  # The keys below hold identical values today. They are still separate so each
  # can evolve on its own without dragging the others along.
  _alphanumeric_30 = {
    length           = 30
    special          = false
    override_special = null
    min_upper        = 1
    min_lower        = 1
    min_numeric      = 1
    min_special      = 0
  }

  policies = {
    rds_master         = local._alphanumeric_30
    rds_app            = local._alphanumeric_30
    elasticache_auth   = local._alphanumeric_30
    msk_scram          = local._alphanumeric_30
    postgres_incluster = local._alphanumeric_30
    redis_incluster    = local._alphanumeric_30
    generic            = local._alphanumeric_30
  }

  resolved = {
    for name, credential in var.credentials : name => merge(
      local.policies[credential.policy],
      { keepers = credential.keepers },
    )
  }

  # Secret path convention: <organisation>/<env>/<service>/<binding>[/<instance>]
  #
  # MSK is carved out because AWS refuses to associate a SCRAM secret whose
  # name does not start with AmazonMSK_ — the path convention cannot apply
  # there, so the same components are flattened into a legal name.
  secret_names = {
    for name, entry in var.publish : name => (
      var.credentials[name].policy == "msk_scram"
      ? join("_", concat(
        ["AmazonMSK_${var.organisation}", entry.environment, entry.service, entry.binding],
        entry.instance == null ? [] : [entry.instance],
      ))
      : join("/", concat(
        [var.organisation, entry.environment, entry.service, entry.binding],
        entry.instance == null ? [] : [entry.instance],
      ))
    )
  }
}
