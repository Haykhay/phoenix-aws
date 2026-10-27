locals {
  # The platform's network settings (spec.network), validated by context.
  platform_network = module.context.platform_network
  central_egress   = try(local.platform_network.egress_mode, "central") == "central"

  # The tier decides the segment.
  tier_segments = {
    sandbox = "non-production"
    stage   = "non-production"
    uat     = "non-production"
    prod    = "production"
  }

  # Networking account: owns the transit gateways and keeps their facts in its
  # own remote state. From the YAML so no account ID is hardcoded here.
  network_settings = try(local.config.providers.network, {})
  # Only the account ID is configured; the role is its deploy role
  # (module.context.role_name).
  network_account_id = try(tostring(local.network_settings.account_id), null)
  network_role_arn   = local.network_account_id == null ? null : "arn:aws:iam::${local.network_account_id}:role/${module.context.role_name}"
  network_configured = local.network_account_id != null && try(local.network_settings.state_bucket, null) != null && local.platform_network != null
  network_state = {
    bucket     = try(local.network_settings.state_bucket, null)
    region     = try(local.network_settings.state_region, null)
    kms_key_id = try(local.network_settings.state_kms_key_id, null)
  }

  # This region's networking `region` unit: transit gateway, segment tables,
  # IPAM pools. Empty until the region's network exists.
  region_state = try(data.terraform_remote_state.region[0].outputs, {})
  tgw_id       = try(local.region_state.transit_gateway_id, null)

  # Forwarding rules shared from the hub (dns_forwarding), associated with
  # every VPC. Rules are regional: each region's hub unit shares its own.
  resolver_rule_ids = try(data.aws_route53_resolver_rules.shared[0].resolver_rule_ids, [])
  resolver_rule_associations = {
    for pair in setproduct(sort(tolist(local.resolver_rule_ids)), keys(local.vpcs)) :
    "${pair[0]}/${pair[1]}" => { rule_id = pair[0], vpc_name = pair[1] }
  }
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "region" {
  count   = local.network_configured ? 1 : 0
  backend = "s3"

  config = {
    bucket     = local.network_state.bucket
    key        = "platform-network/${local.region}/region/terraform.tfstate"
    region     = local.network_state.region
    encrypt    = true
    kms_key_id = local.network_state.kms_key_id
    assume_role = {
      role_arn = local.network_role_arn
    }
  }

  defaults = {}
}

data "aws_route53_resolver_rules" "shared" {
  count = length(try(local.platform_network.dns_forwarding, {})) > 0 ? 1 : 0

  rule_type    = "FORWARD"
  share_status = "SHARED_WITH_ME"
}
