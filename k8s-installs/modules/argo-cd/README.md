# argo-cd

One [Argo CD](https://argo-cd.readthedocs.io) per cluster (chart `7.9.1`, Argo
CD 2.14, pinned) in `argocd`. Part of the **delivery** set, installed with every
workload type; Kargo uses it to sync promoted versions.

| `spec` | Default | |
|---|---|---|
| `repo_url` | **required** | the GitHub repository the bootstrap app watches, e.g. `git@github.com:acme/phoenix-apps.git` |
| `bootstrap_path` | `clusters/helm` | chart path in that repo |
| `ecr_cache_prefix` | `artifactory` | the group account's ECR pull-through prefix, for OCI Helm charts |

- **Bootstrap:** an `Application` syncing `<bootstrap_path>` with the values file
  `clusters/<env_id>-<cluster>.yaml` from the same repo.
- **Repository access:** an ED25519 deploy key generated here. Add output
  `repo_public_key` to the GitHub repo as a read-only deploy key. The chart's
  built-in known hosts already include github.com.
- **OCI charts:** from the group account's ECR (`repo-server` has Pod Identity
  read on `<ecr_cache_prefix>/*`; registry credentials refresh every 6h through
  an external-secrets `ECRAuthorizationToken`).
- **UI:** `https://argocd-<cluster>.<internal zone>`, an HTTPRoute on istio's
  internal gateway with an external-dns record (output `url`). Local admin only
  for now (password in output `admin_secret`); Entra SSO comes with Backstage's
  Entra toggle.
- **Secrets:** `<organisation>/<env_id>/argo-cd/<cluster>/{admin,repo-ssh-key}`.

Needs, applied first: istio (route), external-secrets (ECR credentials),
cert-manager (through istio).
