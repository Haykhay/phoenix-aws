# CreatedBy is captured once and frozen.
resource "terraform_data" "cluster_created_by" {
  for_each = local.clusters

  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

module "eks" {
  for_each = local.clusters
  source   = "terraform-aws-modules/eks/aws"
  version  = "20.28.0"

  vpc_id       = try(local.cluster_networks[each.key].vpc_id, null)
  subnet_ids   = local.cluster_subnet_ids[each.key]
  cluster_name = each.value.cluster_name

  # An IAM name_prefix caps at 38 characters, which "<cluster>-cluster-"
  # overruns for a personal environment (research-sandbox-jdoe-euw1-1-eks-cluster-
  # is 39). The exact name "<cluster>-cluster" has IAM's full 64.
  iam_role_use_name_prefix = false

  cluster_version                          = each.value.version
  cluster_endpoint_public_access           = each.value.endpoint_public_access
  enable_irsa                              = each.value.enable_irsa
  enable_cluster_creator_admin_permissions = each.value.enable_cluster_creator_admin_permissions
  cluster_enabled_log_types                = each.value.cluster_enabled_log_types

  eks_managed_node_group_defaults = {
    cluster_version              = each.value.version
    iam_role_additional_policies = local.node_role_policies[each.key]
  }
  cluster_security_group_additional_rules = local.endpoint_ingress_rules

  cluster_addons          = local.effective_cluster_addons[each.key]
  eks_managed_node_groups = each.value.node_groups
  access_entries          = local.access_entries[each.key]
  node_security_group_additional_rules = {
    allow_http_for_alb_health_check = {
      description = "Allow checking the health checks of instances in the ALB target group"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      type        = "ingress"
      self        = true
    }
  }

  tags = local.tags[each.key]
}

module "aws_ebs_csi_pod_identity" {
  for_each = local.ebs_csi_clusters
  source   = "terraform-aws-modules/eks-pod-identity/aws"
  version  = "1.4.1"

  name                      = coalesce(try(each.value.pod_identity.aws_ebs_csi.name, null), "aws-ebs-csi")
  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns = distinct(concat(
    [module.eks[each.key].kms_key_arn],
    try(each.value.pod_identity.aws_ebs_csi.kms_key_arns, [])
  ))

  association_defaults = {
    namespace       = try(each.value.pod_identity.aws_ebs_csi.namespace, "kube-system")
    service_account = try(each.value.pod_identity.aws_ebs_csi.service_account, "ebs-csi-controller-sa")
  }

  associations = {
    ebs_csi = {
      cluster_name = module.eks[each.key].cluster_name
    }
  }

  tags = local.tags[each.key]
}

# Phase 3: all user-configured addons, created after Pod Identity associations
# are in place so addon pods can assume their roles on first start.
resource "aws_eks_addon" "cluster_addons" {
  for_each = local.post_pi_addons

  cluster_name  = module.eks[each.value.cluster_key].cluster_name
  addon_name    = each.value.addon_name
  addon_version = local.resolved_addon_version[each.key]

  configuration_values        = try(each.value.configuration_values, null)
  resolve_conflicts_on_create = try(each.value.resolve_conflicts_on_create, "OVERWRITE")
  resolve_conflicts_on_update = try(each.value.resolve_conflicts_on_update, "OVERWRITE")

  tags = local.tags[each.value.cluster_key]

  depends_on = [module.aws_ebs_csi_pod_identity]
}

# Guardrails that must hold before anything is created.
resource "terraform_data" "validation" {
  count = local.config.enabled ? 1 : 0

  input = local.default_cluster_name

  lifecycle {
    precondition {
      condition     = length(local.clusters) > 0
      error_message = "core-platform is enabled but no clusters are configured. Add at least one entry under spec.clusters."
    }
    precondition {
      condition     = alltrue([for name, network in local.cluster_networks : network != null])
      error_message = "No network for cluster(s) ${join(", ", [for name, network in local.cluster_networks : name if network == null])}: core-network has no state for this environment/scope (apply it first), or a cluster's `vpc` names a VPC core-network does not have."
    }
    precondition {
      condition     = contains(keys(local.clusters), local.default_cluster_name)
      error_message = "spec.default_cluster must name one of the configured clusters (${join(", ", keys(local.clusters))}). It is only optional when exactly one cluster is configured."
    }
    precondition {
      condition = alltrue([
        for name, cluster in local.clusters : try(trimspace(cluster.version), "") != ""
      ])
      error_message = "Every cluster needs a Kubernetes version. Set `version` on the cluster, or in cluster_defaults for all of them."
    }
    precondition {
      condition     = length(local.addon_pin_conflicts) == 0
      error_message = "Addon pin(s) ${join(", ", local.addon_pin_conflicts)} are shared by clusters on different Kubernetes versions. Pin per cluster, or drop the pin to resolve the latest compatible version for each."
    }
    precondition {
      condition     = alltrue([for name, conflicts in local.access_entry_conflicts : length(conflicts) == 0])
      error_message = "A principal (or entry name) is in both access_entries.admin/admin_role_names and access_entries.view on the same cluster: ${jsonencode({ for name, conflicts in local.access_entry_conflicts : name => conflicts if length(conflicts) > 0 })}. EKS allows one access entry per principal per cluster — keep it in one of them."
    }
    precondition {
      condition     = length(distinct([for name, cluster in local.clusters : cluster.cluster_name])) == length(local.clusters)
      error_message = "Every cluster needs a unique cluster_name. Set it per cluster rather than in cluster_defaults, or leave it unset to derive it from the map key."
    }
  }
}
