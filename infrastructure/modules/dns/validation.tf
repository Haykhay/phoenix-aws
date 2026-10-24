# A hosted zone has no region. Declared per region it would create one zone per
# region for the same name, each with its own name servers, racing over the NS
# delegation in the parent.
resource "terraform_data" "validation" {
  input = local.scope

  lifecycle {
    precondition {
      condition     = local.scope == "global"
      error_message = "dns belongs in the global scope: drop `region` from its YAML (environments/<tier>/<env_id>/global/dns.yaml)."
    }
    # An apex domain (example.com) has no parent zone we own; delegating it
    # would write an NS record into "com". The label count of a registrable
    # domain depends on the public suffix, so this catches the common
    # single-suffix case; set parent_zone_name for anything it gets wrong.
    precondition {
      condition = alltrue([
        for key, zone in local.zones_delegate :
        try(local.config.zones[key].parent_zone_name, null) != null || length(split(".", zone.public_zone_name)) > 2
      ])
      error_message = "Zone(s) ${join(", ", [for key, zone in local.zones_delegate : key if try(local.config.zones[key].parent_zone_name, null) == null && length(split(".", zone.public_zone_name)) <= 2])} look like apex domains: set delegate_public_zone: false (an apex has no parent we own), or parent_zone_name."
    }
    # One zone serving both roles: public_zone_exists alone decides create vs
    # adopt, so an explicit internal_zone_exists that disagrees is a mistake.
    precondition {
      condition = alltrue([
        for key, zone in local.zones :
        !zone.shared_zone || try(local.config.zones[key].internal_zone_exists, zone.public_zone_exists) == zone.public_zone_exists
      ])
      error_message = "A zone used for both roles (internal_zone_name == public_zone_name) sets internal_zone_exists differently from public_zone_exists; public_zone_exists alone decides create vs adopt, so drop internal_zone_exists or make them match."
    }
    precondition {
      condition     = length(local.zones_delegate) == 0 || local.management_account_id != null
      error_message = "A zone is delegated into its parent (delegate_public_zone defaults to true) but spec.providers.management.account_id (the delegated admin account holding the parent zones) is not set. Set it, or set delegate_public_zone: false for an apex domain."
    }
    precondition {
      condition     = local.management_account_id == null || can(regex("^[0-9]{12}$", local.management_account_id))
      error_message = "spec.providers.management.account_id must be a 12-digit AWS account ID (quote it in YAML)."
    }
  }
}
