locals {
  # Resource-set level shape, from the YAML `spec`. `vpcs` is a map of named VPCs; `vpc_defaults`
  # holds settings shared by all of them so they are written once.
  resource_set_defaults = {
    # The YAML file existing is what enables a unit; `enabled: false` is a
    # kill switch that plans a destroy of everything in it.
    enabled      = true
    default_vpc  = null
    providers    = {}
    vpc_defaults = tomap({})
    vpcs         = tomap({})
  }

  config = merge(local.resource_set_defaults, module.context.spec)

  # Per-VPC defaults. Anything here can be overridden in `vpc_defaults` (for every
  # VPC in the environment) or on an individual entry of `vpcs`.
  #
  # VPC endpoints and NAT gateways default to off: they are per-VPC costs
  # (~14 interface endpoints x AZ, plus NAT hours) and only the default VPC
  # normally warrants them. Turn them on explicitly per VPC.
  vpc_defaults = {
    name    = null
    pool    = null
    netmask = 18

    # Pin the pool by ID instead of finding it by its "<tier>/<region>"
    # description -- for an account that sees more than one matching pool.
    ipam_pool_id = null
    azs          = tolist([])

    enable_nat_gateway = false
    single_nat_gateway = true
    enable_vpn_gateway = false

    enable_vpc_endpoints = false
    endpoint_services = tolist([
      "s3",
      "secretsmanager",
      "logs",
      "monitoring",
      "events",
      "sns",
      "sts",
      "ecr.api",
      "ecr.dkr",
      "ec2",
      "autoscaling",
      "ssm",
      "ssmmessages",
      "ec2messages",
      "elasticloadbalancing",
    ])

    enable_tgw_attachment          = false
    enable_tgw_association         = true
    enable_tgw_propagation         = false
    enable_tgw_share               = false
    enable_tgw_peering_routes      = false
    tgw_id                         = null
    tgw_route_table_id             = null
    tgw_propagation_route_table_id = null
    tgw_destination_cidrs          = tolist([])
    tgw_peering_return_cidrs       = tolist([])

    # Load balancer subnet discovery tags (see aws_ec2_tag.internal_elb).
    # Opt-in: turning it on for a VPC that already has internal load
    # balancers makes the AWS Load Balancer Controller want to move them.
    enable_elb_subnet_tags = false
  }

  effective_vpc_defaults = merge(local.vpc_defaults, lookup(local.config, "vpc_defaults", {}))

  merged_vpcs = {
    for vpc_name, vpc in local.config.vpcs : vpc_name => merge(local.effective_vpc_defaults, vpc)
  }

  # ---------------------------------------------------------------------------
  # NAMING
  #
  # `base_name_prefix` (`<env_id>-<region code>`, e.g. research-sandbox-euw1)
  # comes from modules/context, the single place the naming scheme is written
  # and the line to change when the Phoenix naming convention is
  # decided. It is still Proposed.
  #
  # It names the resources that belong to the account/region rather than to one
  # VPC (the TGW RAM share), and every per-VPC name is derived from it below.
  # Everything after that (subnet names, endpoint names, the endpoint security
  # group, the TGW attachment) is built from the per-VPC `name`, so nothing here
  # hardcodes a scheme.
  #
  # The unique integer cluster suffix 1–20 applies to clusters and their
  # associated resources, not to VPCs.
  # ---------------------------------------------------------------------------
  name_prefix = local.base_name_prefix

  # Resolved VPC set. Keys are the VPC names downstream resource sets bind to.
  #
  # The per-VPC `name` override is resolved after the defaults merge, so
  # setting it in `vpc_defaults` is honoured rather than silently ignored;
  # main.tf requires the resulting names to be unique.
  vpcs = {
    for vpc_name, vpc in local.merged_vpcs : vpc_name => merge(vpc, {
      name = coalesce(vpc.name, "${local.name_prefix}-${vpc_name}")
    }) if local.config.enabled
  }

  # Ownership. Per item where a module creates several.
  default_ownership_tags = try(module.context.config.tags, {})

  # Config wins over the captured value, so an existing VPC keeps its creator.
  vpc_ownership_tags = {
    for vpc_name, vpc in local.vpcs : vpc_name => {
      for key, value in merge(
        local.default_ownership_tags,
        try(vpc.tags, {}),
        { CreatedBy = coalesce(
          try(vpc.tags.CreatedBy, null),
          try(local.default_ownership_tags.CreatedBy, null),
          terraform_data.vpc_created_by[vpc_name].output,
        ) },
      ) : key => tostring(value)
    }
  }

  # The VPC resource sets bind to when they do not name one explicitly. With a
  # single VPC configured the designation is unambiguous, so it is optional.
  default_vpc_name = coalesce(
    try(local.config.default_vpc, null),
    length(local.vpcs) == 1 ? keys(local.vpcs)[0] : null,
    "__unset__",
  )

  # ---------------------------------------------------------------------------
  # IPAM
  #
  # Every VPC takes its block from IPAM: `pool` + `netmask`. IPAM's atomic
  # allocation is what keeps VPCs from overlapping. `pool` names a tier ("nonprod", "prod", "infrastructure"); the pool shared
  # to this account for that tier and region is found by its description,
  # "<tier>/<region>". Subnets are not configured for a pool VPC: they are
  # carved from the allocated block in a fixed layout, one per AZ (3 AZs):
  #
  #   platform  quarters 0-2               (/20s in a /18): EKS nodes and pods
  #   data      1/16ths 12-14 (last quarter) (/22s in a /18): RDS, cache, MSK, TGW
  #   public    1/64ths 60-62 (last 1/16th)  (/24s in a /18)
  #
  # The last 1/64th is left free. Each subnet is its own cidrsubnet() over a
  # fixed range: the CIDR is unknown until apply, and cidrsubnets() of an
  # unknown block would make the list length unknown too, which the VPC module
  # cannot count at plan time.
  # ---------------------------------------------------------------------------
  # A VPC still carrying the literal-CIDR keys is rejected (main.tf), never
  # half-honoured.
  literal_network_keys = ["cidr", "private_subnets_data", "private_subnets_platform", "public_subnets"]

  vpc_cidrs = {
    for vpc_name, vpc in local.vpcs : vpc_name => aws_vpc_ipam_pool_cidr_allocation.this[vpc_name].cidr
  }

  subnets = {
    for vpc_name, vpc in local.vpcs : vpc_name => {
      platform = [for i in range(3) : cidrsubnet(local.vpc_cidrs[vpc_name], 2, i)]
      data     = [for i in range(3) : cidrsubnet(local.vpc_cidrs[vpc_name], 4, 12 + i)]
      public   = [for i in range(3) : cidrsubnet(local.vpc_cidrs[vpc_name], 6, 60 + i)]
    }
  }

  private_subnets_all = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => concat(local.subnets[vpc_name].data, local.subnets[vpc_name].platform)
  }

  data_subnet_count = {
    for vpc_name, vpc in local.vpcs : vpc_name => length(local.subnets[vpc_name].data)
  }

  # Mirrors terraform-aws-vpc: one private route table unless NAT is enabled
  # per subnet. Derived from config so it is known at plan time and usable as a
  # for_each key component.
  private_route_table_count = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => (!vpc.enable_nat_gateway || vpc.single_nat_gateway) ? 1 : length(local.private_subnets_all[vpc_name])
  }

  # --- Subsets of local.vpcs, by the feature they opted into ---

  endpoint_vpcs = { for vpc_name, vpc in local.vpcs : vpc_name => vpc if vpc.enable_vpc_endpoints }

  gateway_s3_vpcs = {
    for vpc_name, vpc in local.endpoint_vpcs :
    vpc_name => vpc if contains(vpc.endpoint_services, "s3")
  }

  interface_endpoints = {
    for endpoint in flatten([
      for vpc_name, vpc in local.endpoint_vpcs : [
        for service in vpc.endpoint_services : {
          key      = "${vpc_name}/${service}"
          vpc_name = vpc_name
          service  = service
        } if service != "s3"
      ]
    ]) : endpoint.key => endpoint
  }

  tgw_vpcs = { for vpc_name, vpc in local.vpcs : vpc_name => vpc if vpc.enable_tgw_attachment }

  tgw_association_vpcs = {
    for vpc_name, vpc in local.tgw_vpcs : vpc_name => vpc if vpc.enable_tgw_association
  }

  tgw_propagation_vpcs = {
    for vpc_name, vpc in local.tgw_vpcs : vpc_name => vpc if vpc.enable_tgw_propagation
  }

  # Each VPC's private subnets are created as one list, data subnets first. Split
  # it back into its two roles so downstream resource sets bind to the right one
  # (EKS on platform, RDS/cache/MSK on data).
  data_subnet_ids = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => slice(module.vpc[vpc_name].private_subnets, 0, local.data_subnet_count[vpc_name])
  }

  platform_subnet_ids = {
    for vpc_name, vpc in local.vpcs :
    vpc_name => slice(
      module.vpc[vpc_name].private_subnets,
      local.data_subnet_count[vpc_name],
      length(local.private_subnets_all[vpc_name]),
    )
  }

  # Subnets internal load balancers may use: where EKS runs. Platform subnets,
  # or every private subnet for a VPC that has none (core-platform's rule).
  elb_tag_vpcs = { for vpc_name, vpc in local.vpcs : vpc_name => vpc if vpc.enable_elb_subnet_tags }

  elb_internal_subnet_ids = {
    for vpc_name, vpc in local.elb_tag_vpcs :
    vpc_name => length(local.subnets[vpc_name].platform) > 0 ? local.platform_subnet_ids[vpc_name] : module.vpc[vpc_name].private_subnets
  }
  # From config, so aws_ec2_tag's for_each keys are known at plan time even
  # before the subnets (and their IDs) exist.
  elb_internal_subnet_count = {
    for vpc_name, vpc in local.elb_tag_vpcs :
    vpc_name => length(local.subnets[vpc_name].platform) > 0 ? length(local.subnets[vpc_name].platform) : length(local.private_subnets_all[vpc_name])
  }

  # Routes from each VPC's private route tables towards the transit gateway.
  tgw_routes = {
    for route in flatten([
      for vpc_name, vpc in local.tgw_vpcs : [
        for route_table_index in range(local.private_route_table_count[vpc_name]) : [
          for cidr in vpc.tgw_destination_cidrs : {
            key               = "${vpc_name}/${route_table_index}/${cidr}"
            vpc_name          = vpc_name
            route_table_index = route_table_index
            cidr              = cidr
          }
        ]
      ]
    ]) : route.key => route
  }
}
