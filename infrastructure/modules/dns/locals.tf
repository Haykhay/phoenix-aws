locals {
  defaults = {
    # The YAML file existing enables the unit; `enabled: false` is a kill switch.
    enabled   = true
    zones     = {}
    providers = {}
  }

  config = merge(local.defaults, module.context.spec)

  # Delegated admin account holding the parent zones (providers.tf,
  # aws.management). Only its ID is configured; the role name is fixed.
  management_account_id = try(tostring(local.config.providers.management.account_id), null)
  management_role_arn   = local.management_account_id == null ? null : "arn:aws:iam::${local.management_account_id}:role/${module.context.role_name}"

  zones = local.config.enabled ? {
    for key, zone in local.config.zones : key => {
      public_zone_name     = zone.public_zone_name
      internal_zone_name   = zone.internal_zone_name
      public_zone_exists   = try(zone.public_zone_exists, false)
      internal_zone_exists = try(zone.internal_zone_exists, false)

      parent_zone_name = try(
        zone.parent_zone_name,
        join(".", slice(
          split(".", zone.public_zone_name),
          1,
          length(split(".", zone.public_zone_name)),
        )),
      )

      delegate_public_zone = try(zone.delegate_public_zone, true)

      # One zone serving both roles, for an account whose internal records
      # already live in its public zone (mgmt.example.com). There is then no
      # second zone to create or adopt, and no NS record to write: an NS
      # record for a zone's own name inside itself would overwrite its apex NS.
      shared_zone = zone.internal_zone_name == zone.public_zone_name

      tags = merge(try(local.config.tags, {}), try(zone.tags, {}))
    }
  } : {}

  single_zone_key = try(one(keys(local.zones)), null)

  zones_public_create   = { for k, z in local.zones : k => z if !z.public_zone_exists }
  zones_public_adopt    = { for k, z in local.zones : k => z if z.public_zone_exists }
  zones_internal_create = { for k, z in local.zones : k => z if !z.shared_zone && !z.internal_zone_exists }
  zones_internal_adopt  = { for k, z in local.zones : k => z if !z.shared_zone && z.internal_zone_exists }
  zones_internal_ns     = { for k, z in local.zones : k => z if !z.shared_zone }
  zones_delegate        = { for k, z in local.zones : k => z if z.delegate_public_zone }

  public_zone_ids = {
    for key, zone in local.zones : key => zone.public_zone_exists ? (
      data.aws_route53_zone.public[key].zone_id
      ) : (
      aws_route53_zone.public[key].zone_id
    )
  }

  zone_ids = {
    for key, zone in local.zones : key => {
      public = local.public_zone_ids[key]
      internal = zone.shared_zone ? local.public_zone_ids[key] : (
        zone.internal_zone_exists ? (
          data.aws_route53_zone.internal[key].zone_id
          ) : (
          aws_route53_zone.internal[key].zone_id
        )
      )
    }
  }

  ownership_tags = {
    for key, zone in local.zones : key => {
      for tag_key, value in merge(
        try(module.context.config.tags, {}),
        zone.tags,
        { CreatedBy = coalesce(
          try(zone.tags.CreatedBy, null),
          try(module.context.config.tags.CreatedBy, null),
          terraform_data.created_by.output,
        ) },
      ) : tag_key => tostring(value)
    }
  }

  zone_name_servers = {
    for key, zone in local.zones : key => {
      public = zone.public_zone_exists ? (
        data.aws_route53_zone.public[key].name_servers
        ) : (
        aws_route53_zone.public[key].name_servers
      )
      internal = zone.shared_zone ? null : (
        zone.internal_zone_exists ? (
          data.aws_route53_zone.internal[key].name_servers
          ) : (
          aws_route53_zone.internal[key].name_servers
        )
      )
    }
  }
}
