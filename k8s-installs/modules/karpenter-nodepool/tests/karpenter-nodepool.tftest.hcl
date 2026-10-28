# IAM resources validate policy JSON, so the mocked document is a real (empty) policy.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  config_file = "tests/fixtures/karpenter-nodepool.l4.yaml"
}

override_data {
  target = module.cluster.data.terraform_remote_state.core_platform
  values = {
    outputs = {
      clusters = {
        "1" = {
          cluster_name                       = "research-sandbox-euw1-1-eks"
          cluster_endpoint                   = "https://ABC.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
          cluster_kms_key_arn                = "arn:aws:kms:eu-west-1:111111111111:key/1234"
          node_security_group_id             = "sg-123"
          vpc_id                             = "vpc-123"
          node_subnet_ids                    = ["subnet-p1", "subnet-p2", "subnet-p3"]
          karpenter = {
            controller_role_arn = "arn:aws:iam::111111111111:role/research-sandbox-euw1-1-karpenter-controller"
            node_role_name      = "research-sandbox-euw1-1-karpenter-node"
            node_role_arn       = "arn:aws:iam::111111111111:role/research-sandbox-euw1-1-karpenter-node"
            queue_name          = "research-sandbox-euw1-1-karpenter"
            namespace           = "karpenter"
            service_account     = "karpenter"
          }
        }
      }
    }
  }
}

override_data {
  target = module.cluster.data.terraform_remote_state.dns
  values = {
    outputs = {
      zones = {
        "zone-1" = {
          public_zone_id     = "Z1PUB"
          public_zone_name   = "sandbox.research.example.com"
          internal_zone_id   = "Z1INT"
          internal_zone_name = "internal.sandbox.research.example.com"
        }
      }
    }
  }
}

run "gpu_pool_from_instance" {
  command = plan

  assert {
    condition     = helm_release.this[0].name == "karpenter-nodepool-l4" && helm_release.this[0].namespace == "karpenter"
    error_message = "one release per GPU type, named after the instance"
  }
  assert {
    condition = alltrue([
      yamldecode(helm_release.this[0].values[0]).name == "gpu-l4",
      yamldecode(helm_release.this[0].values[0]).instanceFamilies[0] == "g6",
      yamldecode(helm_release.this[0].values[0]).gpuCountMax == 1,
      yamldecode(helm_release.this[0].values[0]).nodeClass.role == "research-sandbox-euw1-1-karpenter-node",
    ])
    error_message = "NodePool/EC2NodeClass gpu-<instance> from spec (families, max GPUs) and core-platform's node role"
  }
}

run "two_gpu_types_do_not_collide" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.a10g.yaml"
  }

  assert {
    condition     = helm_release.this[0].name == "karpenter-nodepool-a10g" && yamldecode(helm_release.this[0].values[0]).name == "gpu-a10g"
    error_message = "a second GPU type gets its own release and pool"
  }
}

run "families_required" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.bad.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.disabled.yaml"
  }

  assert {
    condition     = length(helm_release.this) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}

run "on_demand_by_default" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).capacityTypes == ["on-demand"] && yamldecode(helm_release.this[0].values[0]).nodeClass.capacityReservations == []
    error_message = "a pool with no reservations stays on-demand"
  }
  assert {
    condition     = output.efa == false && length(helm_release.efa_device_plugin) == 0 && length(aws_security_group.efa) == 0
    error_message = "EFA is off by default"
  }
}

run "reservations_used_first" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.h100.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).nodeClass.capacityReservations == [{ id = "cr-0123" }]
    error_message = "the EC2NodeClass selects the named reservation"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).capacityTypes == ["reserved", "on-demand"]
    error_message = "reserved first, then on-demand"
  }
  assert {
    condition     = output.capacity_reservations == [{ id = "cr-0123" }]
    error_message = "the pool reports the reservations it uses"
  }
}

run "reserved_only" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.h200.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).capacityTypes == ["reserved"]
    error_message = "capacity_types: [] with reservations means reserved only"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).nodeClass.capacityReservations == [{ tags = { team = "research" } }]
    error_message = "a reservation can be selected by tags"
  }
}

run "no_capacity_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.nocap.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "efa_pool" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.h200efa.yaml"
  }

  override_resource {
    target          = aws_security_group.efa
    values          = { id = "sg-efa" }
    override_during = plan
  }

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).efa == true && output.efa == true
    error_message = "the pool labels its nodes phoenix/efa=true and reports efa"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).nodeClass.securityGroupIds == ["sg-123", "sg-efa"]
    error_message = "EFA nodes join the EFA security group beside the node security group"
  }
  assert {
    condition = alltrue([
      aws_security_group.efa[0].vpc_id == "vpc-123",
      aws_vpc_security_group_ingress_rule.efa_self[0].referenced_security_group_id == aws_vpc_security_group_ingress_rule.efa_self[0].security_group_id,
      aws_vpc_security_group_egress_rule.efa_self[0].ip_protocol == "-1",
    ])
    error_message = "EFA nodes get a security group that allows all traffic from and to itself"
  }
  assert {
    condition     = helm_release.efa_device_plugin[0].version == "v0.5.33" && yamldecode(helm_release.efa_device_plugin[0].values[0]).nodeSelector == { "phoenix/gpu" = "h200efa" }
    error_message = "the pool installs the pinned EFA device plugin on its own nodes"
  }
}

run "efa_needs_capable_family" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.l4efa.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "nvidia_by_default" {
  command = plan

  assert {
    condition = alltrue([
      output.accelerator == "nvidia",
      yamldecode(helm_release.this[0].values[0]).accelerator.taint == "nvidia.com/gpu",
      yamldecode(helm_release.this[0].values[0]).accelerator.resource == "nvidia.com/gpu",
    ])
    error_message = "pools are NVIDIA unless told otherwise"
  }
}

run "neuron_pool" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.trn2.yaml"
  }

  assert {
    condition = alltrue([
      output.accelerator == "neuron",
      yamldecode(helm_release.this[0].values[0]).accelerator.name == "neuron",
      yamldecode(helm_release.this[0].values[0]).accelerator.taint == "aws.amazon.com/neuron",
      yamldecode(helm_release.this[0].values[0]).accelerator.resource == "aws.amazon.com/neuron",
      yamldecode(helm_release.this[0].values[0]).nodeClass.amiAlias == "al2023@latest",
    ])
    error_message = "a Neuron pool taints aws.amazon.com/neuron, labels phoenix/accelerator=neuron, limits Neuron devices and uses AL2023 (Karpenter picks the Neuron variant)"
  }
}

run "unknown_accelerator_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.amd.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "gpu_limit_fits_big_nodes" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.trn2.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).gpuLimit == 32
    error_message = "the default limit is max(8, 2 nodes' worth): a 16-device trn2 node (or a 2-node replica) can launch"
  }
}

run "gpu_limit_below_one_node_rejected" {
  command = plan

  variables {
    config_file = "tests/fixtures/karpenter-nodepool.tight.yaml"
  }

  expect_failures = [terraform_data.validation]
}
