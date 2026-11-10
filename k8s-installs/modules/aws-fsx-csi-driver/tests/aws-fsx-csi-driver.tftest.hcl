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
  config_file = "tests/fixtures/default.yaml"
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
          vpc_id                             = "vpc-123"
          node_subnet_ids                    = ["subnet-p1", "subnet-p2", "subnet-p3"]
          node_security_group_id             = "sg-123"
        }
      }
    }
  }
}

# Not used here; the cluster module reads it for every component.
override_data {
  target = module.cluster.data.terraform_remote_state.dns
  values = { outputs = {} }
}

override_data {
  target = data.terraform_remote_state.model_cache
  values = {
    outputs = {
      file_system_id      = "fs-0123456789abcdef0"
      dns_name            = "fs-0123456789abcdef0.fsx.eu-west-1.amazonaws.com"
      mount_name          = "abcdefgh"
      weights_path_prefix = "/weights"
    }
  }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition     = helm_release.driver[0].version == "1.18.0" && helm_release.driver[0].namespace == "kube-system"
    error_message = "the driver chart is pinned"
  }
  assert {
    condition     = yamldecode(helm_release.driver[0].values[0]).node.tolerateAllTaints == true
    error_message = "the node daemonset runs on every node, GPU (nvidia.com/gpu) and Neuron (aws.amazon.com/neuron) pools included"
  }
  assert {
    condition     = helm_release.volume[0].namespace == "models"
    error_message = "the claim lives where vLLM runs"
  }
}

run "volume_comes_from_state" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.volume[0].values[0]).fsx.volumeHandle == "fs-0123456789abcdef0"
    error_message = "the PV's csi.volumeHandle is the model cache's file system ID"
  }
  assert {
    condition     = yamldecode(helm_release.volume[0].values[0]).fsx.dnsName == "fs-0123456789abcdef0.fsx.eu-west-1.amazonaws.com" && yamldecode(helm_release.volume[0].values[0]).fsx.mountName == "abcdefgh"
    error_message = "volumeAttributes dnsname and mountname come from model-cache state"
  }
  assert {
    condition     = output.pvc_name == "model-cache" && output.mount_path == "/models" && output.sub_path == "weights"
    error_message = "vllm mounts claim model-cache, subPath weights, at /models"
  }
}

# Not every cluster serves models: without a model cache the driver still
# runs for phoenix-shared; vllm itself refuses to start without the cache.
run "no_model_cache_installs_driver_only" {
  command = plan

  override_data {
    target = data.terraform_remote_state.model_cache
    values = { outputs = {} }
  }

  assert {
    condition     = length(helm_release.driver) == 1 && length(helm_release.volume) == 0 && length(kubernetes_storage_class_v1.shared) == 1
    error_message = "no model cache: the driver and phoenix-shared, no model-cache claim"
  }
}

run "shared_class_uses_fsx" {
  command = plan

  assert {
    condition = alltrue([
      try(kubernetes_storage_class_v1.shared[0].metadata[0].name, "") == "phoenix-shared",
      try(kubernetes_storage_class_v1.shared[0].storage_provisioner, "") == "fsx.csi.aws.com",
      try(kubernetes_storage_class_v1.shared[0].reclaim_policy, "") == "Delete",
      try(kubernetes_storage_class_v1.shared[0].parameters.deploymentType, "") == "PERSISTENT_2",
      try(kubernetes_storage_class_v1.shared[0].parameters.perUnitStorageThroughput, "") == "125",
      try(kubernetes_storage_class_v1.shared[0].parameters.subnetId, "") == "subnet-p1",
      try(kubernetes_storage_class_v1.shared[0].parameters.extraTags, "") == "PhoenixCluster=research-sandbox-euw1-1-eks",
    ])
    error_message = "phoenix-shared provisions a PERSISTENT_2 FSx for Lustre file system per claim, in the cluster's node subnets, tagged with the cluster, deleted with its claim"
  }
}

run "driver_role_scoped_to_cluster" {
  command = plan

  assert {
    condition = alltrue([
      try(aws_eks_pod_identity_association.driver[0].namespace, "") == "kube-system",
      try(aws_eks_pod_identity_association.driver[0].service_account, "") == "fsx-csi-controller-sa",
      try(aws_eks_pod_identity_association.driver[0].cluster_name, "") == "research-sandbox-euw1-1-eks",
    ])
    error_message = "the driver's controller gets its own role through Pod Identity"
  }
  assert {
    condition = alltrue([
      for s in try(data.aws_iam_policy_document.driver.statement, []) : contains(["DescribeFileSystems", "ServiceLinkedRole"], s.sid) || anytrue([
        for c in s.condition : contains(["aws:ResourceTag/PhoenixCluster", "aws:RequestTag/PhoenixCluster"], c.variable) && toset(c.values) == toset(["research-sandbox-euw1-1-eks"])
      ])
    ]) && length(try(data.aws_iam_policy_document.driver.statement, [])) == 4
    error_message = "the driver may create file systems only tagged with this cluster, and change or delete only those"
  }
}

run "lustre_ports_from_nodes" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["988", "1018-1023"] : try(aws_vpc_security_group_ingress_rule.lustre_from_nodes[k].referenced_security_group_id, "") == "sg-123"
    ])
    error_message = "nodes reach the file systems on Lustre's ports (988, 1018-1023)"
  }
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/disabled.yaml"
  }

  assert {
    condition     = length(helm_release.driver) + length(helm_release.volume) + length(kubernetes_storage_class_v1.shared) + length(aws_iam_role.driver) + length(aws_security_group.lustre) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
