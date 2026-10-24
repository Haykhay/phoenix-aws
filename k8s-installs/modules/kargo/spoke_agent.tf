# ── Management cluster: provision a service account for remote spoke access ───
# The spoke controller on each remote cluster needs a kubeconfig pointing at
# this cluster's Kubernetes API so it can watch and act on Kargo CRDs that
# live here. The SA is bound to kargo-controller ClusterRole (Kargo CRD
# read/write) and a long-lived token is bundled into a full kubeconfig YAML
# stored in Secrets Manager for the spoke to consume.
#
# Token rotation: time_rotating fires after 300 days and cascades through
# replace_triggered_by to recreate the SA token secret and SM version in a
# single apply. No manual tainting needed.

resource "time_rotating" "spoke_agent_token" {
  count         = local.is_management ? 1 : 0
  rotation_days = 300
}

resource "kubernetes_service_account_v1" "spoke_agent" {
  count = local.is_management ? 1 : 0
  metadata {
    name      = "kargo-spoke-agent"
    namespace = local.namespace
  }
  depends_on = [helm_release.this]
}

resource "kubernetes_cluster_role_binding_v1" "spoke_agent" {
  count = local.is_management ? 1 : 0
  metadata {
    name = "kargo-spoke-agent"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kargo-controller"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
    namespace = local.namespace
  }
}

resource "kubernetes_cluster_role_binding_v1" "spoke_agent_rollouts" {
  count = local.is_management ? 1 : 0
  metadata {
    name = "kargo-spoke-agent-rollouts"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kargo-controller-rollouts"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
    namespace = local.namespace
  }
}

resource "kubernetes_cluster_role_binding_v1" "spoke_agent_argocd" {
  count = local.is_management ? 1 : 0
  metadata {
    name = "kargo-spoke-agent-argocd"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kargo-controller-argocd"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
    namespace = local.namespace
  }
}

resource "kubernetes_cluster_role_binding_v1" "spoke_agent_read_secrets" {
  count = local.is_management ? 1 : 0
  metadata {
    name = "kargo-spoke-agent-read-secrets"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "kargo-controller-read-secrets"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
    namespace = local.namespace
  }
}

# Heartbeat lease: spoke controller renews a Lease on the management cluster
# so the management controller knows the spoke is alive. The lease permissions
# are in a namespace-scoped Role (not ClusterRole) in the kargo namespace.
resource "kubernetes_role_binding_v1" "spoke_agent_leases" {
  count = local.is_management ? 1 : 0
  metadata {
    name      = "kargo-spoke-agent-leases"
    namespace = local.namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "kargo-controller"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
    namespace = local.namespace
  }
}

# Creates a long-lived SA token secret. The Kubernetes token controller
# populates data["token"] asynchronously; the provider waits for it.
resource "kubernetes_secret_v1" "spoke_agent_token" {
  count = local.is_management ? 1 : 0
  metadata {
    name      = "kargo-spoke-agent-token"
    namespace = local.namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
    }
  }
  type       = "kubernetes.io/service-account-token"
  depends_on = [kubernetes_cluster_role_binding_v1.spoke_agent]

  lifecycle {
    replace_triggered_by = [time_rotating.spoke_agent_token]
  }
}

resource "aws_secretsmanager_secret" "remote_kubeconfig" {
  count                   = local.is_management ? 1 : 0
  name                    = "${local.secret_path}/remote-kubeconfig"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "remote_kubeconfig" {
  count     = local.is_management ? 1 : 0
  secret_id = aws_secretsmanager_secret.remote_kubeconfig[0].id

  secret_string = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = "management"
      cluster = {
        certificate-authority-data = module.cluster.cluster_ca_data
        server                     = module.cluster.cluster_endpoint
      }
    }]
    contexts = [{
      name = "management"
      context = {
        cluster = "management"
        user    = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
      }
    }]
    current-context = "management"
    users = [{
      name = kubernetes_service_account_v1.spoke_agent[0].metadata[0].name
      user = {
        token = kubernetes_secret_v1.spoke_agent_token[0].data["token"]
      }
    }]
  })

  lifecycle {
    ignore_changes       = [secret_string]
    replace_triggered_by = [kubernetes_secret_v1.spoke_agent_token]
  }
}
