mock_provider "aws" {}

variables {
  config_file = "tests/fixtures/model-cache.1.yaml"
}

# The environment's VPC, with the S3 gateway endpoint model serving needs.
override_data {
  target = data.terraform_remote_state.core_network
  values = {
    outputs = {
      default_vpc_name = "vpc-1"
      long_live        = false
      networks = {
        "vpc-1" = {
          vpc_id           = "vpc-123"
          vpc_cidr_block   = "10.64.0.0/18"
          vpc_endpoint_ids = { s3 = "vpce-s3" }
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.core_platform
  values = {
    outputs = {
      clusters = {
        "1" = {
          cluster_name           = "research-sandbox-euw1-1-eks"
          vpc                    = "vpc-1"
          vpc_id                 = "vpc-123"
          node_subnet_ids        = ["subnet-p1", "subnet-p2", "subnet-p3"]
          node_security_group_id = "sg-nodes"
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.model_store
  values = {
    outputs = { bucket_name = "research-shared-euw1-model-weights-111111111111" }
  }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition = alltrue([
      aws_fsx_lustre_file_system.this.deployment_type == "PERSISTENT_2",
      aws_fsx_lustre_file_system.this.storage_capacity == 1200,
      aws_fsx_lustre_file_system.this.per_unit_storage_throughput == 250,
      one(aws_fsx_lustre_file_system.this.subnet_ids) == "subnet-p1",
    ])
    error_message = "one PERSISTENT_2 file system, 1200 GiB at 250 MB/s/TiB, in the cluster's first node subnet"
  }
  assert {
    condition = alltrue([
      aws_fsx_data_repository_association.this.file_system_path == "/weights",
      aws_fsx_data_repository_association.this.data_repository_path == "s3://research-shared-euw1-model-weights-111111111111/",
      toset(aws_fsx_data_repository_association.this.s3[0].auto_import_policy[0].events) == toset(["NEW", "CHANGED", "DELETED"]),
    ])
    error_message = "the cache lazy-loads the whole weights bucket at /weights and follows its changes"
  }
  assert {
    condition = alltrue([
      for port in [988, 1018] :
      contains([for r in aws_vpc_security_group_ingress_rule.lustre_from_nodes : r.from_port], port)
    ]) && alltrue([for r in aws_vpc_security_group_ingress_rule.lustre_from_nodes : r.cidr_ipv4 == "10.64.0.0/18" && r.referenced_security_group_id == null])
    error_message = "cluster nodes reach Lustre on 988 and 1018-1023, by the VPC's CIDR: a rule naming the node security group would block deleting it when core-platform is torn down under a long-lived cache"
  }
  assert {
    condition     = output.weights_path_prefix == "/weights"
    error_message = "consumers learn where the weights sit inside the file system"
  }
}

run "s3_gateway_endpoint_required" {
  command = plan

  override_data {
    target = data.terraform_remote_state.core_network
    values = {
      outputs = {
        default_vpc_name = "vpc-1"
        long_live        = false
        networks         = { "vpc-1" = { vpc_id = "vpc-123", vpc_cidr_block = "10.64.0.0/18", vpc_endpoint_ids = {} } }
      }
    }
  }

  expect_failures = [terraform_data.validation]
}

run "long_lived_cache_needs_long_lived_network" {
  command = plan

  variables {
    config_file = "tests/fixtures/long-lived/model-cache.1.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "long_lived_cache_in_long_lived_network" {
  command = plan

  variables {
    config_file = "tests/fixtures/long-lived/model-cache.1.yaml"
  }

  override_data {
    target = data.terraform_remote_state.core_network
    values = {
      outputs = {
        default_vpc_name = "vpc-1"
        long_live        = true
        networks         = { "vpc-1" = { vpc_id = "vpc-123", vpc_cidr_block = "10.64.0.0/18", vpc_endpoint_ids = { s3 = "vpce-s3" } } }
      }
    }
  }

  assert {
    condition     = aws_fsx_lustre_file_system.this.deployment_type == "PERSISTENT_2"
    error_message = "a long-lived cache plans inside a long-lived network"
  }
}

run "missing_model_store_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.model_store
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "unknown_cluster_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/unknown-cluster/model-cache.9.yaml"
  }

  expect_failures = [terraform_data.validation]
}
