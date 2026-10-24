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

# Read-only, value by value: no ListSecrets / DescribeParameters, so the
# operator cannot even enumerate other environments' secret names.
data "aws_iam_policy_document" "this" {
  statement {
    sid       = "SecretsManager"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = local.secrets_manager_arns
  }

  statement {
    sid       = "SSMParameterStore"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = local.ssm_parameter_arns
  }

  statement {
    sid       = "ECRAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(local.ecr_pull_repos) > 0 ? [1] : []
    content {
      sid    = "ECRPull"
      effect = "Allow"
      actions = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
      ]
      resources = [for repo in local.ecr_pull_repos : "arn:aws:ecr:${local.region}:${local.account_id}:repository/${repo}"]
    }
  }

  dynamic "statement" {
    for_each = length(local.kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "KMSDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = local.kms_key_arns
    }
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

# The association existing in the AWS API does not mean EKS's Pod Identity
# admission webhook will act on it yet; a pod created right after can miss
# credential injection and stay permanently unauthorized (injection happens
# only at admission). This buffer closes that gap.
resource "time_sleep" "pod_identity_propagation" {
  count           = local.config.enabled ? 1 : 0
  depends_on      = [aws_eks_pod_identity_association.this]
  create_duration = "20s"
}
