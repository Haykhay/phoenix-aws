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
  description = "The unit's AWS account ID."
  value       = tostring(local.config.account_id)
}

output "region_code" {
  description = "Short region code (euw1); null in the global scope."
  value       = local.region_code
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
  description = "S3 backend settings shared by every unit of the account."
  value       = local.state
}

output "state_key" {
  description = "This unit's state key."
  value       = local.state_key
}

output "network" {
  description = "The selected VPC from core-network's `networks` output, or null."
  value       = local.network
}

output "networks" {
  description = "Every VPC from core-network's state, keyed by VPC key; {} when it has no state."
  value       = local.networks
}

output "role_name" {
  description = "Name of the deploy role in every account; ARNs are arn:aws:iam::<account id>:role/<role_name>."
  value       = local.role_name
}

output "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR)."
  value       = var.pipeline_user
}
