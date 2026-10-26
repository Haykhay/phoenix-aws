output "zones" {
  description = "Every hosted zone pair in this resource set, keyed by its config name."
  value = {
    for key, zone in local.zones : key => {
      public_zone_id     = local.zone_ids[key].public
      public_zone_name   = zone.public_zone_name
      internal_zone_id   = local.zone_ids[key].internal
      internal_zone_name = zone.internal_zone_name
    }
  }
}

output "zone_names" {
  description = "Config keys of every zone in this resource set."
  value       = keys(local.zones)
}

output "public_zone_id" {
  description = "With one zone only: public zone ID."
  value       = local.single_zone_key != null ? local.zone_ids[local.single_zone_key].public : null
}

output "public_zone_name" {
  description = "With one zone only: public zone name."
  value       = local.single_zone_key != null ? local.zones[local.single_zone_key].public_zone_name : null
}

output "internal_zone_id" {
  description = "With one zone only: internal (private) zone ID."
  value       = local.single_zone_key != null ? local.zone_ids[local.single_zone_key].internal : null
}

output "internal_zone_name" {
  description = "With one zone only: internal zone name."
  value       = local.single_zone_key != null ? local.zones[local.single_zone_key].internal_zone_name : null
}
