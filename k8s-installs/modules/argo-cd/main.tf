resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !local.config.enabled || local.repo_url != null
      error_message = "spec.repo_url is required: the GitHub repository Argo CD's bootstrap app watches (add the module's repo_public_key to it as a read-only deploy key)."
    }
    precondition {
      condition     = !local.config.enabled || local.dns != null
      error_message = "argo-cd's UI route needs the cluster's DNS zone from infrastructure's dns unit."
    }
  }
}

resource "helm_release" "this" {
  count            = local.config.enabled ? 1 : 0
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = local.config.chart_version
  namespace        = local.namespace
  create_namespace = true

  values = [templatefile("${path.module}/manifests/values.yaml.tpl", {
    url_host            = local.hostname
    admin_password_hash = local.argocd_admin_password_hash
  })]

  depends_on = [terraform_data.validation, time_sleep.pod_identity_propagation]
}

# The repository Secret for the bootstrap app (deploy key generated here).
resource "helm_release" "repo_secret" {
  count     = local.config.enabled ? 1 : 0
  name      = "argocd-repo-secret"
  chart     = "${path.module}/manifests/repo-secret"
  namespace = local.namespace

  set           = [{ name = "repoUrl", value = local.repo_url }]
  set_sensitive = [{ name = "sshPrivateKey", value = local.argocd_repo_ssh_private_key }]

  depends_on = [helm_release.this]
}

# OCI Helm repository credentials for the group account's ECR (pull-through cache).
resource "helm_release" "ecr_credentials" {
  count     = local.config.enabled ? 1 : 0
  name      = "argocd-ecr-credentials"
  chart     = "${path.module}/manifests/ecr-credentials"
  namespace = local.namespace

  values = [yamlencode({ region = local.region, accountIds = [local.account_id] })]

  depends_on = [helm_release.this]
}

resource "helm_release" "bootstrap" {
  count     = local.config.enabled ? 1 : 0
  name      = "argo-bootstrap"
  chart     = "${path.module}/manifests/argo-bootstrap"
  namespace = local.namespace

  values = [yamlencode({
    repoUrl       = local.repo_url
    bootstrapPath = local.config.bootstrap_path
    valuesFile    = local.values_file
  })]

  depends_on = [helm_release.this]
}

# The UI on istio's internal gateway, with a DNS record from external-dns.
resource "helm_release" "route" {
  count     = local.config.enabled ? 1 : 0
  name      = "argocd-route"
  chart     = "${path.module}/manifests/route"
  namespace = local.namespace

  values = [yamlencode({
    name     = "argocd"
    hostname = local.hostname
    gateway  = { name = "istio-internal", namespace = "istio-system" }
    service  = { name = "argocd-server", port = 80 }
  })]

  depends_on = [helm_release.this]
}
