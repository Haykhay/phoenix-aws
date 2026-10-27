resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = local.network.first_hub == local.region
      error_message = "hybrid runs in the first hub region (${coalesce(local.network.first_hub, "unset")}), not ${local.region}."
    }
    precondition {
      condition     = !local.vpn || (try(local.settings.customer_gateway.ip, null) != null && try(local.settings.customer_gateway.bgp_asn, null) != null)
      error_message = "hybrid ${local.mode} needs hybrid_settings.customer_gateway.ip and .bgp_asn."
    }
    precondition {
      condition     = !local.dx || (try(local.settings.dx_gateway_asn, null) != null && length(local.connections) == (local.dual_dx ? 2 : 1))
      error_message = "hybrid ${local.mode} needs hybrid_settings.dx_gateway_asn and ${local.dual_dx ? 2 : 1} connection(s) ([i] near hub_regions[i])."
    }
    precondition {
      condition     = try(local.first.transit_gateway_id, null) != null
      error_message = "Apply the region unit in ${local.region} before hybrid."
    }
  }
}
