# Single binary, objects under <bucket>/${loki_prefix}/ (Loki's storage_prefix
# allows no slash, so the cluster name is part of it).
deploymentMode: SingleBinary
serviceAccount:
  create: true
  name: loki
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  schemaConfig:
    configs:
      - from: "2026-01-01"
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: index_
          period: 24h
  storage:
    type: s3
    bucketNames:
      chunks: ${bucket}
      ruler: ${bucket}
      admin: ${bucket}
    s3:
      region: ${region}
    use_thanos_objstore: true
    object_store:
      type: s3
      storage_prefix: ${loki_prefix}
      s3:
        endpoint: s3.${region}.amazonaws.com
        region: ${region}
singleBinary:
  replicas: 1
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
chunksCache:
  enabled: false
resultsCache:
  enabled: false
lokiCanary:
  enabled: false
test:
  enabled: false
minio:
  enabled: false
