# Single binary, objects under <bucket>/${tempo_prefix}/.
serviceAccount:
  create: true
  name: tempo
tempo:
  storage:
    trace:
      backend: s3
      s3:
        bucket: ${bucket}
        prefix: ${tempo_prefix}
        endpoint: s3.${region}.amazonaws.com
        region: ${region}
