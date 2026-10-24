data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count              = local.config.enabled ? 1 : 0
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "ChangeRecordSets"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [for id in local.route53_zone_ids : "arn:aws:route53:::hostedzone/${id}"]
  }

  statement {
    sid    = "ListZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "this" {
  count  = local.config.enabled ? 1 : 0
  name   = local.role_name
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "this" {
  count      = local.config.enabled ? 1 : 0
  role       = aws_iam_role.this[0].name
  policy_arn = aws_iam_policy.this[0].arn
}

resource "aws_eks_pod_identity_association" "this" {
  count           = local.config.enabled ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = local.namespace
  service_account = local.service_account_name
  role_arn        = aws_iam_role.this[0].arn
}

# The AWS API call above completing doesn't mean EKS's Pod Identity admission
# webhook is immediately ready to act on it — a pod created right after can
# still miss credential injection (confirmed live: happened to 3 of 8
# Pod-Identity-consuming modules on one fresh cluster bring-up, silently —
# the pod stays Running, just permanently unauthorized, since injection only
# happens at admission and never retroactively). This buffer closes that gap.
resource "time_sleep" "pod_identity_propagation" {
  count           = local.config.enabled ? 1 : 0
  depends_on      = [aws_eks_pod_identity_association.this]
  create_duration = "20s"
}
