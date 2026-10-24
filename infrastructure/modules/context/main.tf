locals {
  config = yamldecode(file(var.config_file))

  # Every account has a deploy role of this one name (created by account
  # vending), so a cross-account reference is only an account ID:
  # arn:aws:iam::<account id>:role/<role_name>.
  role_name = "Terraform-Role"
  spec      = try(local.config.spec, {})

  organisation = local.config.organisation
  group        = local.config.group
  environment  = local.config.environment
  requester    = try(local.config.requester, null)
  tier         = local.config.tier

  # The unique key of an environment: path, state key and name prefix all start
  # with it, so two requesters in one group never collide.
  env_id = join("-", compact([local.group, local.environment, local.requester]))

  # A unit without a region is global (dns). Its provider still needs a region
  # to call AWS; us-east-1 homes the global service endpoints.
  scope  = try(local.config.region, null) == null ? "global" : local.config.region
  region = local.scope == "global" ? try(local.config.global_region, "us-east-1") : local.scope

  # AWS region -> short code: the "A2" prefix AWS itself uses in AZ IDs
  # (euw1-az1). Full region names overrun tight identifier limits (an
  # ElastiCache replication group ID caps at 40). Indexed, not looked up: an
  # unmapped region fails here rather than half-renaming an environment.
  region_codes = {
    "ap-northeast-2" = "apne2"
    "eu-central-1"   = "euc1"
    "eu-west-1"      = "euw1"
    "eu-west-2"      = "euw2"
    "sa-east-1"      = "sae1"
    "us-east-1"      = "use1"
  }
  region_code = local.scope == "global" ? null : local.region_codes[local.scope]

  name_prefix = try(local.config.name_prefix, join("-", compact([local.env_id, local.region_code])))

  identifier = "^[a-z][a-z0-9]*(-[a-z0-9]+)*$"
  identifiers_valid = alltrue([
    for v in compact([local.organisation, local.group, local.environment, local.requester]) : can(regex(local.identifier, v))
  ])

  owner_tags = try(local.config.tags, {})
  tags = merge(
    {
      Project      = "Phoenix"
      Organisation = local.organisation
      Group        = local.group
      Environment  = local.env_id
      Tier         = local.tier
      Scope        = local.scope
      Region       = local.region
      ResourceSet  = var.resource_set
      ManagedBy    = "Terraform"
    },
    local.requester == null ? {} : { Requester = local.requester },
    { for k, v in local.owner_tags : k => tostring(v) },
  )

  state = {
    bucket     = local.config.state.bucket
    region     = local.config.state.region
    kms_key_id = try(local.config.state.kms_key_id, null)
  }
  state_key = "${local.env_id}/${local.scope}/${var.resource_set}/terraform.tfstate"
}

# Common network state of this environment/scope. try()'d all the way
# down: a destroy of a consumer after core-network is gone must still plan.
data "terraform_remote_state" "core_network" {
  count   = var.network ? 1 : 0
  backend = "s3"

  config = {
    bucket = local.state.bucket
    region = local.state.region
    key    = "${local.env_id}/${local.scope}/core-network/terraform.tfstate"
  }

  defaults = {}
}

locals {
  core_network_outputs = try(data.terraform_remote_state.core_network[0].outputs, {})
  networks             = try(local.core_network_outputs.networks, {})
  vpc_name             = try(local.spec.vpc, local.core_network_outputs.default_vpc_name, null)
  network              = local.vpc_name == null ? null : try(local.core_network_outputs.networks[local.vpc_name], null)
}
