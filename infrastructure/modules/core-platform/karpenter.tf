# AWS side of Karpenter, per cluster that sets `karpenter.enabled`. The
# controller itself (Helm) lives in k8s-installs' karpenter module, which
# reads the role, node role and queue names back from the `clusters` output.
#
# Everything the submodule creates stays together here: its controller policy
# is built from its own queue ARN and node role ARN, so splitting the controller
# role off into k8s-installs would mean re-deriving those statements by hand.

locals {
  karpenter_clusters = {
    for name, cluster in local.clusters :
    name => cluster if try(cluster.karpenter.enabled, false)
  }

  # Strip the -eks suffix so names read sandbox-euw1-2-karpenter-node, not
  # sandbox-euw1-2-eks-karpenter-node.
  karpenter_name_base = {
    for name, cluster in local.karpenter_clusters :
    name => trimsuffix(cluster.cluster_name, "-eks")
  }

  # The submodule's v1 policy was written against Karpenter 1.0. These are the
  # permissions the upstream reference policy has gained since, up to 1.15.
  # They live in their own managed policy (below), not in the submodule's:
  # IAM caps a managed policy at 6,144 characters excluding whitespace, the
  # v1 policy alone is ~5,550 and these add ~900 — combined, CreatePolicy fails
  # with LimitExceeded (PolicySize). Upstream's CloudFormation splits the same
  # permissions across five managed policies for this reason. The additions:
  # capacity reservations, placement groups, node repair (reboot) and instance
  # profile garbage collection. Re-check against
  # website/content/en/<version>/getting-started/getting-started-with-karpenter/cloudformation.yaml
  # in aws/karpenter-provider-aws whenever k8s-installs bumps the chart.
  karpenter_extra_policy_statements = {
    for name, cluster in local.karpenter_clusters : name => [
      {
        sid     = "AllowScopedEC2CapacityAccessActions"
        actions = ["ec2:RunInstances", "ec2:CreateFleet"]
        resources = [
          "arn:aws:ec2:${local.region}:*:capacity-reservation/*",
          "arn:aws:ec2:${local.region}:*:placement-group/*",
        ]
      },
      {
        sid       = "AllowScopedReboot"
        actions   = ["ec2:RebootInstances"]
        resources = ["arn:aws:ec2:${local.region}:*:instance/*"]
        conditions = [
          {
            test     = "StringEquals"
            variable = "aws:ResourceTag/kubernetes.io/cluster/${cluster.cluster_name}"
            values   = ["owned"]
          },
          {
            test     = "StringLike"
            variable = "aws:ResourceTag/karpenter.sh/nodepool"
            values   = ["*"]
          },
        ]
      },
      {
        sid = "AllowAdditionalRegionalReadActions"
        actions = [
          "ec2:DescribeCapacityReservations",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribePlacementGroups",
        ]
        resources = ["*"]
        conditions = [
          {
            test     = "StringEquals"
            variable = "aws:RequestedRegion"
            values   = [local.region]
          },
        ]
      },
      {
        sid       = "AllowUnscopedInstanceProfileListAction"
        actions   = ["iam:ListInstanceProfiles"]
        resources = ["*"]
      },
    ]
  }
}

# Controller role + Pod Identity association, node role + EKS access entry,
# and the SQS interruption queue with its EventBridge rules. Same mirror and
# ref as module.eks, so the two are bumped together.
module "karpenter" {
  for_each = local.karpenter_clusters
  source   = "terraform-aws-modules/eks/aws//modules/karpenter"
  version  = "20.28.0"

  cluster_name = module.eks[each.key].cluster_name

  enable_v1_permissions           = true
  enable_pod_identity             = true
  create_pod_identity_association = true
  # Must match what k8s-installs' karpenter module deploys into — it reads
  # both back from the `clusters` output rather than assuming them.
  namespace       = try(each.value.karpenter.namespace, "karpenter")
  service_account = try(each.value.karpenter.service_account, "karpenter")

  iam_role_name              = "${local.karpenter_name_base[each.key]}-karpenter-controller"
  iam_role_use_name_prefix   = false
  iam_policy_name            = "${local.karpenter_name_base[each.key]}-karpenter-controller"
  iam_policy_use_name_prefix = false
  iam_role_policies = {
    extra = aws_iam_policy.karpenter_controller_extra[each.key].arn
  }

  enable_spot_termination = try(each.value.karpenter.interruption_handling, true)
  queue_name              = "${local.karpenter_name_base[each.key]}-karpenter"

  # Same managed policies as the managed node group roles, so Karpenter nodes
  # behave like the rest of the fleet. The submodule adds
  # AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy and
  # AmazonEC2ContainerRegistryReadOnly on top.
  node_iam_role_name                = "${local.karpenter_name_base[each.key]}-karpenter-node"
  node_iam_role_use_name_prefix     = false
  node_iam_role_additional_policies = local.node_role_policies[each.key]

  tags = local.tags[each.key]
}

# The post-1.0 permissions above, as a second managed policy on the same
# controller role (see karpenter_extra_policy_statements for why it is separate).
data "aws_iam_policy_document" "karpenter_controller_extra" {
  for_each = local.karpenter_clusters

  dynamic "statement" {
    for_each = local.karpenter_extra_policy_statements[each.key]

    content {
      sid       = statement.value.sid
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = try(statement.value.conditions, [])

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_policy" "karpenter_controller_extra" {
  for_each = local.karpenter_clusters

  name        = "${local.karpenter_name_base[each.key]}-karpenter-controller-extra"
  description = "Karpenter controller permissions added upstream after 1.0 (capacity reservations, placement groups, node repair, instance profile GC)"
  policy      = data.aws_iam_policy_document.karpenter_controller_extra[each.key].json
  tags        = local.tags[each.key]
}
