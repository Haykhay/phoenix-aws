api:
  enabled: true
  host: "${api_host}"
  adminAccount:
    enabled: true
    passwordHash: "${admin_password_hash}"
    tokenSigningKey: "${token_signing_key}"
    tokenTTL: 24h
  # Maps shard/cluster names to their per-cluster Argo CD URLs for UI deep-links
  argocd:
    urls:
%{ for cluster, url in argocd_urls ~}
      ${cluster}: "${url}"
%{ endfor ~}
  tls:
    enabled: false
  # Exposed through istio (HTTPRoute in this module), not an ingress.
  ingress:
    enabled: false
managementController:
  enabled: true

garbageCollector:
  enabled: true
  maxRetainedPromotions: 5
  minPromotionDeletionAge: "168h"
  maxRetainedFreight: 10
  minFreightDeletionAge: "168h"

controller:
  enabled: true
  shardName: "${shard_name}"
  argocd:
    integrationEnabled: true
    namespace: argocd
