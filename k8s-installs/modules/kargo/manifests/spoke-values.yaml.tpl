api:
  enabled: false

managementController:
  enabled: false

garbageCollector:
  enabled: false

controller:
  enabled: true
  shardName: "${shard_name}"
  argocd:
    integrationEnabled: true
    namespace: argocd
  kubeconfigSecrets:
    kargo: kargo-management-kubeconfig
