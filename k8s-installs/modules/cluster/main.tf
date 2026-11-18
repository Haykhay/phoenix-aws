# Which cluster a k8s-installs unit runs against, read from infrastructure's
# state: core-platform (regional) for the cluster, dns (global) for its zone.
# Both reads default to empty so a missing state fails the plan on the
# validation below rather than inside a provider.
data "terraform_remote_state" "core_platform" {
  backend = "s3"
  config = {
    bucket = var.state.bucket
    region = var.state.region
    key    = "${var.env_id}/${var.region}/core-platform/terraform.tfstate"
  }
  defaults = {}
}

data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = var.state.bucket
    region = var.state.region
    key    = "${var.env_id}/global/dns/terraform.tfstate"
  }
  defaults = {}
}

locals {
  found   = can(data.terraform_remote_state.core_platform.outputs.clusters[var.cluster])
  cluster = local.found ? data.terraform_remote_state.core_platform.outputs.clusters[var.cluster] : null
  dns     = try(data.terraform_remote_state.dns.outputs.zones[var.dns_zone], null)

  # Placeholder keeps the providers from seeing null
  # while the validation below fails the plan.
  cluster_name = local.found ? local.cluster.cluster_name : "cluster-missing"
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = local.found
      error_message = "core-platform state for ${var.env_id}/${var.region} has no cluster \"${var.cluster}\". Apply core-platform first, or fix `cluster` in the unit YAML."
    }
  }
}
