output "config" {
  description = "The whole decoded YAML."
  value       = local.config
}

output "spec" {
  description = "The resource set's own settings (YAML `spec`)."
  value       = local.spec
}

output "organisation" {
  description = "organisation from the YAML."
  value       = local.organisation
}

output "group" {
  description = "group from the YAML."
  value       = local.group
}

output "requester" {
  description = "requester from the YAML; null for a shared environment."
  value       = local.requester
}

output "environment" {
  description = "environment from the YAML."
  value       = local.environment
}

output "env_id" {
  description = "<group>-<environment>[-<requester>]: the environment's unique key."
  value       = local.env_id
}

output "tier" {
  description = "sandbox, stage, uat or prod."
  value       = local.tier
}

output "scope" {
  description = "AWS region, or global."
  value       = local.scope
}

output "region" {
  description = "Region the provider talks to (us-east-1 or global_region for global scope)."
  value       = local.region
}

output "account_id" {
  description = "The unit's AWS account ID; null on Azure."
  value       = local.aws_cloud ? tostring(local.config.account_id) : null
}

output "cloud" {
  description = "aws (default when the YAML has no cloud) or azure."
  value       = local.cloud

  precondition {
    condition     = contains(["aws", "azure"], local.cloud)
    error_message = "cloud must be aws or azure, not ${local.cloud}."
  }
}

output "azure" {
  description = "Azure identity {tenant_id, client_id, principal_id, subscription_id}; null on AWS."
  value       = local.azure
}

output "region_code" {
  description = "Short region code (euw1, weu); null in the global scope."
  value       = local.region_code

  precondition {
    condition     = local.region_valid
    error_message = "region ${local.scope} has no short code on ${local.cloud}; Azure regions must be one of: ${join(", ", sort(keys(local.azure_region_codes)))}."
  }
}

output "name_prefix" {
  description = "<env_id>-<region code>; <env_id> for global scope."
  value       = local.name_prefix

  precondition {
    condition     = local.identifiers_valid
    error_message = "organisation, group, environment and requester must be lowercase alphanumeric segments joined by single dashes (^[a-z][a-z0-9]*(-[a-z0-9]+)*$)."
  }
}

output "tags" {
  description = "Default tags for every resource."
  value       = local.tags

  # Nothing is created without an owner and a reason.
  precondition {
    condition     = trimspace(try(tostring(local.owner_tags["owner.team"]), "")) != "" && trimspace(try(tostring(local.owner_tags.Reason), "")) != ""
    error_message = "tags must set owner.team and Reason."
  }

  # Absent means ephemeral; the string "false" would read as truthy.
  precondition {
    condition     = !contains(keys(local.owner_tags), "LongLive") || try(local.owner_tags.LongLive == true || local.owner_tags.LongLive == false, false)
    error_message = "tags.LongLive must be a boolean (true/false), not a string."
  }
}

output "state" {
  description = "Backend settings. AWS: {bucket, region, kms_key_id}, shared by the account. Azure: {subscription_id, resource_group, storage_account, container}, the environment's container."
  value       = local.state
}

output "state_key" {
  description = "This unit's state key."
  value       = local.state_key
}

output "instance" {
  description = "Instance from <unit>.<instance>.yaml; null for a singleton."
  value       = local.instance
}

output "platform_network" {
  description = "spec.network over the platform defaults, plus first_hub and segments {production, non-production, shared}; null without spec.network."
  value       = local.platform_network

  precondition {
    condition     = alltrue(values(local.network_checks))
    error_message = "spec.network is invalid; failing checks: ${join(", ", [for k, ok in local.network_checks : k if !ok])}. address_space must be RFC 1918, must not overlap onprem_cidrs and must hold four blocks at segment_netmask; region_netmask must be longer than segment_netmask; egress_mode is central|independent; hybrid is none|vpn|dx_vpn|dual_dx; 1-2 hub_regions, dual_dx needs 2."
  }
}

output "network" {
  description = "The selected VPC from core-network's `networks` output, or null."
  value       = local.network
}

output "networks" {
  description = "Every VPC from core-network's state, keyed by VPC key; {} when it has no state."
  value       = local.networks
}

output "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR)."
  value       = var.pipeline_user
}

output "floci" {
  description = "True only for an explicit local Floci overlay; never committed for live units."
  value       = local.floci

  precondition {
    condition     = !local.floci || (local.tier == "sandbox" && can(regex("^http://(localhost|127\\.0\\.0\\.1|floci)(:[0-9]+)?$", local.aws_endpoint_url)))
    error_message = "Floci mode is sandbox-only and its endpoint must be local (localhost, 127.0.0.1, or floci)."
  }
}

output "aws_endpoint_url" {
  description = "Local Floci endpoint, null for live AWS."
  value       = local.aws_endpoint_url
}
