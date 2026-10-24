# Pod Identity for the kargo-controller SA on the management cluster.
# Kargo's Warehouse controller uses these credentials to scan ECR for new image
# tags (ambient credential mode — no per-project Kargo Secret needed).
# Only created on the management cluster; spokes have no warehouse controller.

data "aws_iam_policy_document" "pod_identity_assume" {
  count = local.is_management ? 1 : 0

  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "kargo_controller" {
  count = local.is_management ? 1 : 0

  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRRead"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
    ]
    resources = ["arn:aws:ecr:${local.region}:${local.account_id}:repository/*"]
  }
}

resource "aws_iam_role" "kargo_controller" {
  count = local.is_management ? 1 : 0

  name               = "${local.name_prefix}-kargo-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume[0].json
}

resource "aws_iam_policy" "kargo_controller" {
  count = local.is_management ? 1 : 0

  name   = "${local.name_prefix}-kargo-controller"
  policy = data.aws_iam_policy_document.kargo_controller[0].json
}

resource "aws_iam_role_policy_attachment" "kargo_controller" {
  count = local.is_management ? 1 : 0

  role       = aws_iam_role.kargo_controller[0].name
  policy_arn = aws_iam_policy.kargo_controller[0].arn
}

resource "aws_eks_pod_identity_association" "kargo_controller" {
  count = local.is_management ? 1 : 0

  cluster_name    = local.cluster_name
  namespace       = local.namespace
  service_account = "kargo-controller"
  role_arn        = aws_iam_role.kargo_controller[0].arn
}

# The AWS API call above completing doesn't mean EKS's Pod Identity admission
# webhook is immediately ready to act on it — a pod created right after can
# still miss credential injection (confirmed live: happened to 3 of 8
# Pod-Identity-consuming modules on one fresh cluster bring-up, silently —
# the pod stays Running, just permanently unauthorized, since injection only
# happens at admission and never retroactively). This buffer closes that gap.
# helm_release.this must also depend on this directly — previously it only
# depended on the kubeconfig secret, with no ordering against this
# association at all.
resource "time_sleep" "pod_identity_propagation" {
  count           = local.is_management ? 1 : 0
  depends_on      = [aws_eks_pod_identity_association.kargo_controller]
  create_duration = "20s"
}
