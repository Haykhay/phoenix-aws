mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/forwarding.yaml"
}

override_data {
  target = data.terraform_remote_state.region
  values = {
    outputs = {
      transit_gateway_id = "tgw-euw1"
      route_table_ids    = { production = "rtb-prod", "non-production" = "rtb-nonprod", shared = "rtb-shared" }
      pool_ids           = { production = "ipam-pool-prod", "non-production" = "ipam-pool-nonprod", shared = "ipam-pool-shared" }
    }
  }
}

override_data {
  target = data.aws_availability_zones.this
  values = {
    names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  }
}

run "endpoints_and_rules" {
  command = plan

  assert {
    condition     = aws_route53_resolver_endpoint.inbound.direction == "INBOUND" && aws_route53_resolver_endpoint.outbound[0].direction == "OUTBOUND"
    error_message = "inbound and outbound endpoints"
  }
  assert {
    condition     = toset(keys(aws_route53_resolver_rule.forward)) == toset(["corp.local", "lab.local"]) && aws_route53_resolver_rule.forward["corp.local"].rule_type == "FORWARD"
    error_message = "one forward rule per domain"
  }
  assert {
    condition     = toset([for t in aws_route53_resolver_rule.forward["corp.local"].target_ip : t.ip]) == toset(["192.168.1.10", "192.168.1.11"])
    error_message = "a rule forwards to its domain's on-prem resolvers"
  }
  assert {
    condition     = length(aws_ram_resource_association.rules) == 2 && toset([for p in aws_ram_principal_association.rules : p.principal]) == toset(["arn:aws:organizations::999999999999:organization/o-example"])
    error_message = "every rule is shared with share_with"
  }
}

run "dns_vpc_in_shared" {
  command = plan

  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.dns.ipam_pool_id == "ipam-pool-shared" && aws_vpc_ipam_pool_cidr_allocation.dns.netmask_length == 24
    error_message = "the DNS VPC is a /24 from the region's shared pool"
  }
  assert {
    condition     = aws_ec2_transit_gateway_route_table_association.dns.transit_gateway_route_table_id == "rtb-shared"
    error_message = "the DNS VPC is associated with shared"
  }
  assert {
    condition     = toset([for p in aws_ec2_transit_gateway_route_table_propagation.dns : p.transit_gateway_route_table_id]) == toset(["rtb-prod", "rtb-nonprod", "rtb-shared"])
    error_message = "the DNS VPC propagates into all three tables"
  }
  assert {
    condition     = toset([for r in aws_route.dns_to_tgw : r.destination_cidr_block]) == toset(["10.0.0.0/8", "192.168.0.0/16"])
    error_message = "the DNS VPC reaches address_space and on-prem through the transit gateway"
  }
}

run "resolver_reachable_from_platform_and_onprem" {
  command = plan

  assert {
    condition     = toset(flatten([for r in aws_vpc_security_group_ingress_rule.dns : [r.cidr_ipv4]])) == toset(["10.0.0.0/8", "192.168.0.0/16"]) && toset([for r in aws_vpc_security_group_ingress_rule.dns : r.ip_protocol]) == toset(["tcp", "udp"])
    error_message = "DNS (53/tcp+udp) from address_space and on-prem"
  }
}

run "no_forwarding_no_outbound" {
  command = plan

  variables {
    config_file = "tests/fixtures/no_forwarding.yaml"
  }

  assert {
    condition     = length(aws_route53_resolver_endpoint.outbound) == 0 && length(aws_route53_resolver_rule.forward) == 0 && length(aws_ram_resource_share.rules) == 0
    error_message = "inbound only when nothing is forwarded"
  }
}

run "region_must_exist" {
  command = plan

  override_data {
    target = data.terraform_remote_state.region
    values = {
      outputs = {}
    }
  }

  expect_failures = [aws_vpc_ipam_pool_cidr_allocation.dns]
}
