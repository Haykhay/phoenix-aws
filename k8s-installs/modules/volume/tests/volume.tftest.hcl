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
  config_file = "tests/fixtures/volume.data.yaml"
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

run "plans_block_volume" {
  command = plan

  assert {
    condition = alltrue([
      try(helm_release.this[0].name, "") == "volume-data",
      try(helm_release.this[0].namespace, "") == "apps",
      try(helm_release.this[0].create_namespace, false) == true,
      try(helm_release.this[0].wait, true) == false,
    ])
    error_message = "one release per claim, in its namespace (created if missing), not waiting for a pod to bind it"
  }
  assert {
    condition = try(yamldecode(helm_release.this[0].values[0]), null) == {
      name         = "data"
      storageClass = "phoenix-block"
      size         = "50Gi"
      accessMode   = "ReadWriteOnce"
    }
    error_message = "a phoenix-block claim of size_gib, one pod at a time"
  }
}

run "shared_volume_is_read_write_many" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.shared.yaml"
  }

  assert {
    condition     = try(yamldecode(helm_release.this[0].values[0]).storageClass, "") == "phoenix-shared" && try(yamldecode(helm_release.this[0].values[0]).accessMode, "") == "ReadWriteMany"
    error_message = "a phoenix-shared claim is mounted by many pods"
  }
}

run "volume_rejects_unknown_class" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.bad-class.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "volume_requires_size" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.no-size.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "shared_size_in_lustre_steps" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.shared-small.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "volume_rejects_system_namespace" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.system.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "volume_needs_a_name" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.yaml"
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/volume.off.yaml"
  }

  assert {
    condition     = length(helm_release.this) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
