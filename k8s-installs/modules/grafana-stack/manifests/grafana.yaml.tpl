serviceAccount:
  create: true
  name: grafana
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Mimir
        type: prometheus
        uid: mimir
        url: http://mimir-gateway.${namespace}.svc/prometheus
        isDefault: true
      - name: Loki
        type: loki
        uid: loki
        url: http://loki-gateway.${namespace}.svc
      - name: Tempo
        type: tempo
        uid: tempo
        url: http://tempo.${namespace}.svc:3200
      # Credentials from Pod Identity (monitoring/grafana -> CloudWatch read role).
      - name: CloudWatch
        type: cloudwatch
        uid: cloudwatch
        jsonData:
          authType: default
          defaultRegion: ${region}
