data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "repo_server" {
  statement {
    sid       = "ECRGetToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPullHelmCharts"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = local.ecr_pull_arns
  }
}

resource "aws_iam_role" "repo_server" {
  count              = local.config.enabled ? 1 : 0
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_policy" "repo_server" {
  count  = local.config.enabled ? 1 : 0
  name   = local.role_name
  policy = data.aws_iam_policy_document.repo_server.json
}

resource "aws_iam_role_policy_attachment" "repo_server" {
  count      = local.config.enabled ? 1 : 0
  role       = aws_iam_role.repo_server[0].name
  policy_arn = aws_iam_policy.repo_server[0].arn
}

resource "aws_eks_pod_identity_association" "repo_server" {
  count           = local.config.enabled ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = local.namespace
  service_account = local.service_account_name
  role_arn        = aws_iam_role.repo_server[0].arn
}

# The AWS API call above completing doesn't mean EKS's Pod Identity admission
# webhook is immediately ready to act on it — a pod created right after can
# still miss credential injection (confirmed live: happened to 3 of 8
# Pod-Identity-consuming modules on one fresh cluster bring-up, silently —
# the pod stays Running, just permanently unauthorized, since injection only
# happens at admission and never retroactively). This buffer closes that gap.
resource "time_sleep" "pod_identity_propagation" {
  count           = local.config.enabled ? 1 : 0
  depends_on      = [aws_eks_pod_identity_association.repo_server]
  create_duration = "20s"
}
