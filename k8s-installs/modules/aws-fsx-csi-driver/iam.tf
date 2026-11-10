data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# The driver's documented minimum, scoped: it may create file systems only
# tagged with this cluster, and change or delete only those.
data "aws_iam_policy_document" "driver" {
  statement {
    sid       = "ServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "iam:AWSServiceName"
      values   = ["fsx.amazonaws.com"]
    }
  }

  statement {
    sid       = "DescribeFileSystems"
    actions   = ["fsx:DescribeFileSystems"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateTagged"
    actions   = ["fsx:CreateFileSystem", "fsx:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${local.tag_key}"
      values   = [local.cluster_name]
    }
  }

  statement {
    sid       = "ChangeOwn"
    actions   = ["fsx:DeleteFileSystem", "fsx:UpdateFileSystem"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${local.tag_key}"
      values   = [local.cluster_name]
    }
  }
}

resource "aws_iam_role" "driver" {
  count              = local.config.enabled ? 1 : 0
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy" "driver" {
  count  = local.config.enabled ? 1 : 0
  name   = local.role_name
  role   = aws_iam_role.driver[0].id
  policy = data.aws_iam_policy_document.driver.json
}

resource "aws_eks_pod_identity_association" "driver" {
  count           = local.config.enabled ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = "kube-system"
  service_account = local.service_account
  role_arn        = aws_iam_role.driver[0].arn
}

# Pod Identity injects credentials only when a pod is admitted: give the
# association a moment before the controller starts (see external-dns).
resource "time_sleep" "pod_identity_propagation" {
  count           = local.config.enabled ? 1 : 0
  depends_on      = [aws_eks_pod_identity_association.driver]
  create_duration = "20s"
}

# File systems phoenix-shared creates; nodes reach them on Lustre's ports.
resource "aws_security_group" "lustre" {
  count       = local.config.enabled ? 1 : 0
  name        = "${local.name_prefix}-fsx-shared"
  description = "FSx for Lustre file systems of phoenix-shared claims"
  vpc_id      = module.cluster.vpc_id
}

locals {
  lustre_ports = { "988" = [988, 988], "1018-1023" = [1018, 1023] }
}

resource "aws_vpc_security_group_ingress_rule" "lustre_from_nodes" {
  for_each                     = local.config.enabled ? local.lustre_ports : {}
  security_group_id            = aws_security_group.lustre[0].id
  referenced_security_group_id = module.cluster.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value[0]
  to_port                      = each.value[1]
}

resource "aws_vpc_security_group_ingress_rule" "lustre_self" {
  for_each                     = local.config.enabled ? local.lustre_ports : {}
  security_group_id            = aws_security_group.lustre[0].id
  referenced_security_group_id = aws_security_group.lustre[0].id
  ip_protocol                  = "tcp"
  from_port                    = each.value[0]
  to_port                      = each.value[1]
}

resource "aws_vpc_security_group_egress_rule" "lustre_all" {
  count             = local.config.enabled ? 1 : 0
  security_group_id = aws_security_group.lustre[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
