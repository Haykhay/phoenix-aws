locals {
  config = yamldecode(file(var.config_file))

  # The job signs in to the unit's own account through GitHub OIDC
  # (Terraform-Role, or Terraform-Plan-Role on pull requests; ADR-0013), so
  # providers and state reads use the job's credentials as they are.
  spec             = try(local.config.spec, {})
  floci            = try(local.config.floci == true, false)
  aws_endpoint_url = local.floci ? try(tostring(local.config.aws_endpoint_url), "http://localhost:4566") : null

  # aws (the default: a unit without `cloud` is AWS) or azure.
  cloud       = try(local.config.cloud, "aws")
  aws_cloud   = local.cloud == "aws"
  azure_cloud = local.cloud == "azure"
  cloud_valid = local.aws_cloud || local.azure_cloud

  # Azure: the environment's managed identity (Backstage writes it from the
  # environment entity) and its subscription. Null on AWS.
  azure = local.azure_cloud ? {
    tenant_id       = local.config.azure.tenant_id
    client_id       = local.config.azure.client_id
    principal_id    = try(local.config.azure.principal_id, null)
    subscription_id = local.config.subscription_id
  } : null

  organisation = local.config.organisation
  group        = local.config.group
  environment  = local.config.environment
  requester    = try(local.config.requester, null)
  tier         = local.config.tier

  # The unique key of an environment: path, state key and name prefix all start
  # with it, so two requesters in one group never collide.
  env_id = join("-", compact([local.group, local.environment, local.requester]))

  # A unit without a region is global (dns). Its provider still needs a region
  # to call AWS; us-east-1 homes the global service endpoints. On Azure it is
  # the location of the unit's resource group (westeurope unless global_region).
  scope  = try(local.config.region, null) == null ? "global" : local.config.region
  region = local.scope == "global" ? try(local.config.global_region, local.azure_cloud ? "westeurope" : "us-east-1") : local.scope

  # AWS region -> short code: the "A2" prefix AWS itself uses in AZ IDs
  # (euw1-az1). Full region names overrun tight identifier limits (an
  # ElastiCache replication group ID caps at 40). Derived from the direction
  # words, so any region works (ap-southeast-1 -> apse1). Indexed, not looked
  # up: an unknown word (us-gov-west-1) fails here rather than half-renaming
  # an environment.
  directions = {
    north     = "n", south = "s", east = "e", west = "w", central = "c",
    northeast = "ne", northwest = "nw", southeast = "se", southwest = "sw",
  }
  region_parts = split("-", local.scope)
  aws_region_code = local.scope == "global" || !local.aws_cloud ? null : join("", concat(
    [local.region_parts[0]],
    [for p in slice(local.region_parts, 1, length(local.region_parts) - 1) : local.directions[p]],
    [local.region_parts[length(local.region_parts) - 1]],
  ))

  # Azure region names carry no direction words to derive from: an explicit
  # map. A region outside it fails the region_code check (outputs.tf) rather
  # than half-renaming an environment.
  azure_region_codes = {
    westeurope    = "weu", northeurope = "neu", uksouth = "uks", ukwest = "ukw",
    swedencentral = "sec", germanywestcentral = "gwc", francecentral = "frc",
    eastus        = "eus", eastus2 = "eus2", westus2 = "wus2", westus3 = "wus3", centralus = "cus",
  }
  region_code = local.azure_cloud ? (local.scope == "global" ? null : lookup(local.azure_region_codes, local.scope, null)) : local.aws_region_code
  # Only checked for a known cloud: an unknown one fails the cloud check alone.
  region_valid = !local.cloud_valid || local.scope == "global" || local.region_code != null

  # <unit>.<instance>.yaml -> instance (peering.eu-west-1.yaml); singletons have none.
  instance = try(regex("^[^.]+\\.(.+)\\.yaml$", basename(var.config_file))[0], null)

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

  # AWS: the account's S3 bucket. Azure: the environment's own container in
  # the state storage account (env_id unless the YAML names one).
  state = local.azure_cloud ? {
    subscription_id = try(local.config.state.subscription_id, local.config.subscription_id)
    resource_group  = local.config.state.resource_group
    storage_account = local.config.state.storage_account
    container       = try(local.config.state.container, local.env_id)
    } : local.aws_cloud ? {
    bucket     = local.config.state.bucket
    region     = local.config.state.region
    kms_key_id = try(local.config.state.kms_key_id, null)
  } : null
  state_key = "${local.env_id}/${local.scope}/${join(".", compact([var.resource_set, local.instance]))}/terraform.tfstate"

  # The platform's network decisions (spec.network), copied by Backstage into
  # every unit that needs them. Segments are derived here once: block 0
  # production, 1 non-production, 2 shared, 3+ reserved.
  network_settings = try(local.spec.network, null)
  platform_network_settings = local.network_settings == null ? null : merge({
    hub_regions        = []
    tooling_account_id = null
    address_space      = "10.0.0.0/8"
    segment_netmask    = 10
    region_netmask     = 13
    egress_mode        = "central"
    hybrid             = "none"
    onprem_cidrs       = []
    dns_forwarding     = {}
    share_with         = []
  }, local.network_settings)

  address_prefix = local.platform_network_settings == null ? null : tonumber(split("/", local.platform_network_settings.address_space)[1])
  segment_bits   = local.platform_network_settings == null ? null : local.platform_network_settings.segment_netmask - local.address_prefix

  platform_network = local.platform_network_settings == null ? null : merge(local.platform_network_settings, {
    first_hub = try(local.platform_network_settings.hub_regions[0], null)
    # Too small for four blocks: left to the four_blocks check to report.
    segments = local.segment_bits < 2 ? null : { for i, name in ["production", "non-production", "shared"] :
      name => cidrsubnet(local.platform_network_settings.address_space, local.segment_bits, i)
    }
  })

  # CIDR a lies within b. Two CIDRs overlap exactly when one contains the other.
  rfc1918 = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  network_checks = local.platform_network_settings == null ? {} : {
    rfc1918 = anytrue([for b in local.rfc1918 :
      local.address_prefix >= tonumber(split("/", b)[1]) && cidrsubnet("${cidrhost(local.platform_network_settings.address_space, 0)}/${split("/", b)[1]}", 0, 0) == b
    ])
    onprem_disjoint = !anytrue(flatten([for c in local.platform_network_settings.onprem_cidrs : [
      for pair in [[c, local.platform_network_settings.address_space], [local.platform_network_settings.address_space, c]] :
      tonumber(split("/", pair[0])[1]) >= tonumber(split("/", pair[1])[1]) && cidrsubnet("${cidrhost(pair[0], 0)}/${split("/", pair[1])[1]}", 0, 0) == cidrsubnet(pair[1], 0, 0)
    ]]))
    four_blocks   = local.segment_bits >= 2
    region_inside = local.platform_network_settings.region_netmask > local.platform_network_settings.segment_netmask
    egress_mode   = contains(["central", "independent"], local.platform_network_settings.egress_mode)
    hybrid        = contains(["none", "vpn", "dx_vpn", "dual_dx"], local.platform_network_settings.hybrid)
    hub_count     = contains([1, 2], length(local.platform_network_settings.hub_regions))
    dual_dx_hubs  = local.platform_network_settings.hybrid != "dual_dx" || length(local.platform_network_settings.hub_regions) == 2
  }
}

# Common network state of this environment/scope. try()'d all the way
# down: a destroy of a consumer after core-network is gone must still plan.
data "terraform_remote_state" "core_network" {
  count   = var.network && local.aws_cloud ? 1 : 0
  backend = "s3"

  config = {
    bucket = local.state.bucket
    region = local.state.region
    key    = "${local.env_id}/${local.scope}/core-network/terraform.tfstate"
  }

  defaults = {}
}

# The same read on Azure: the environment's container, with the job's identity.
data "terraform_remote_state" "core_network_azure" {
  count   = var.network && local.azure_cloud ? 1 : 0
  backend = "azurerm"

  config = {
    subscription_id      = local.state.subscription_id
    resource_group_name  = local.state.resource_group
    storage_account_name = local.state.storage_account
    container_name       = local.state.container
    key                  = "${local.env_id}/${local.scope}/core-network/terraform.tfstate"
    use_azuread_auth     = true
  }

  defaults = {}
}

locals {
  core_network_outputs = try(
    local.azure_cloud ? data.terraform_remote_state.core_network_azure[0].outputs : data.terraform_remote_state.core_network[0].outputs,
    {},
  )
  networks = try(local.core_network_outputs.networks, {})
  vpc_name = try(local.spec.vpc, local.core_network_outputs.default_vpc_name, null)
  network  = local.vpc_name == null ? null : try(local.core_network_outputs.networks[local.vpc_name], null)
}
