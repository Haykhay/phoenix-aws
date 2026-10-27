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
  # ElastiCache replication group ID caps at 40). Derived from the direction
  # words, so any region works (ap-southeast-1 -> apse1). Indexed, not looked
  # up: an unknown word (us-gov-west-1) fails here rather than half-renaming
  # an environment.
  directions = {
    north     = "n", south = "s", east = "e", west = "w", central = "c",
    northeast = "ne", northwest = "nw", southeast = "se", southwest = "sw",
  }
  region_parts = split("-", local.scope)
  region_code = local.scope == "global" ? null : join("", concat(
    [local.region_parts[0]],
    [for p in slice(local.region_parts, 1, length(local.region_parts) - 1) : local.directions[p]],
    [local.region_parts[length(local.region_parts) - 1]],
  ))

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

  state = {
    bucket     = local.config.state.bucket
    region     = local.config.state.region
    kms_key_id = try(local.config.state.kms_key_id, null)
  }
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
