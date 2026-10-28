# One FSx for Lustre file system per cluster that serves models, linked to the
# group's weights bucket (model-store): the first read of a file loads it from
# S3, later reads are served from Lustre. vLLM pods mount it read-only
# (k8s-installs aws-fsx-csi-driver). Unit file: model-cache.<cluster>.yaml.
#
# Lifecycle is tags.LongLive, written by Backstage from the per-tier platform
# setting: true keeps the warm cache through weekend teardowns (and pays for
# it); false is torn down with the environment. S3 holds the weights either way.

locals {
  defaults = {
    deployment_type      = "PERSISTENT_2"
    storage_capacity_gib = 1200 # PERSISTENT_2 minimum; grows in 2400 GiB steps
    throughput_per_tib   = 250  # MB/s per TiB: 125, 250, 500 or 1000
  }
  config = merge(local.defaults, module.context.spec)

  cluster_key = coalesce(module.context.instance, "missing")
  cluster     = try(data.terraform_remote_state.core_platform.outputs.clusters[local.cluster_key], null)
  network     = try(data.terraform_remote_state.core_network.outputs.networks[local.cluster.vpc], null)
  bucket_name = try(data.terraform_remote_state.model_store.outputs.bucket_name, null)

  long_live         = try(module.context.config.tags.LongLive, false) == true
  network_long_live = try(data.terraform_remote_state.core_network.outputs.long_live, false) == true

  weights_path_prefix = "/weights"
  # Lustre: 988 for the service, 1018-1023 for client traffic.
  lustre_ports = { "988" = [988, 988], "1018-1023" = [1018, 1023] }
}

data "terraform_remote_state" "core_network" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/core-network/terraform.tfstate"
  }
  defaults = {}
}

data "terraform_remote_state" "core_platform" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${local.environment}/${local.region}/core-platform/terraform.tfstate"
  }
  defaults = {}
}

data "terraform_remote_state" "model_store" {
  backend = "s3"
  config = {
    bucket = module.context.state.bucket
    region = module.context.state.region
    key    = "${module.context.group}-shared/${local.region}/model-store/terraform.tfstate"
  }
  defaults = {}
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = module.context.instance != null
      error_message = "model-cache is per cluster: name the file model-cache.<cluster>.yaml."
    }
    precondition {
      condition     = local.cluster != null
      error_message = "no cluster \"${local.cluster_key}\" in core-platform for ${local.environment}/${local.region}: apply core-platform first, or fix the file name."
    }
    precondition {
      condition     = local.bucket_name != null
      error_message = "no weights bucket: apply model-store in ${module.context.group}-shared/${local.region} first."
    }
    precondition {
      condition     = contains(keys(try(local.network.vpc_endpoint_ids, {})), "s3")
      error_message = "VPC ${try(local.cluster.vpc, "?")} has no S3 gateway endpoint: set enable_vpc_endpoints: true with s3 in endpoint_services in core-network, so weights never leave AWS's network."
    }
    # A long-lived file system inside a VPC a teardown deletes would block the
    # VPC's deletion.
    precondition {
      condition     = !local.long_live || local.network_long_live
      error_message = "model-cache is LongLive but core-network for ${local.environment}/${local.region} is not: make the network LongLive too, or set tags.LongLive: false here."
    }
  }
}

resource "aws_security_group" "this" {
  name        = "${local.base_name_prefix}-${local.cluster_key}-model-cache"
  description = "FSx for Lustre model cache for cluster ${local.cluster_key}"
  vpc_id      = try(local.cluster.vpc_id, null)

  depends_on = [terraform_data.validation]
}

resource "aws_vpc_security_group_ingress_rule" "lustre_from_nodes" {
  for_each = local.lustre_ports

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = try(local.cluster.node_security_group_id, null)
  ip_protocol                  = "tcp"
  from_port                    = each.value[0]
  to_port                      = each.value[1]
}

# Lustre servers talk to each other on the same ports.
resource "aws_vpc_security_group_ingress_rule" "lustre_self" {
  for_each = local.lustre_ports

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = aws_security_group.this.id
  ip_protocol                  = "tcp"
  from_port                    = each.value[0]
  to_port                      = each.value[1]
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_fsx_lustre_file_system" "this" {
  deployment_type             = local.config.deployment_type
  storage_capacity            = local.config.storage_capacity_gib
  per_unit_storage_throughput = local.config.throughput_per_tib
  file_system_type_version    = "2.15"
  data_compression_type       = "LZ4"
  subnet_ids                  = [try(local.cluster.node_subnet_ids[0], "subnet-missing")]
  security_group_ids          = [aws_security_group.this.id]

  tags = { Name = "${local.base_name_prefix}-${local.cluster_key}-model-cache", Cluster = local.cluster_key }
}

resource "aws_fsx_data_repository_association" "this" {
  file_system_id                   = aws_fsx_lustre_file_system.this.id
  data_repository_path             = "s3://${coalesce(local.bucket_name, "missing")}/"
  file_system_path                 = local.weights_path_prefix
  batch_import_meta_data_on_create = true

  s3 {
    auto_import_policy {
      events = ["NEW", "CHANGED", "DELETED"]
    }
  }
}
