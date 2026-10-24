# Collection: metrics from annotated pods -> Mimir, every pod's logs -> Loki,
# OTLP traces (4317 gRPC / 4318 HTTP) -> Tempo.
alloy:
  extraPorts:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      protocol: TCP
    - name: otlp-http
      port: 4318
      targetPort: 4318
      protocol: TCP
  configMap:
    content: |
      discovery.kubernetes "pods" {
        role = "pod"
      }

      // Pods that ask for it (prometheus.io/scrape = "true"), plus the GPU
      // operator's DCGM exporter, which it labels app=nvidia-dcgm-exporter.
      discovery.relabel "scrape" {
        targets = discovery.kubernetes.pods.targets
        rule {
          source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape", "__meta_kubernetes_pod_label_app"]
          separator     = ";"
          regex         = "true;.*|.*;nvidia-dcgm-exporter"
          action        = "keep"
        }
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }
      }

      prometheus.scrape "pods" {
        targets    = discovery.relabel.scrape.output
        forward_to = [prometheus.remote_write.mimir.receiver]
      }

      prometheus.remote_write "mimir" {
        endpoint {
          url = "http://mimir-gateway.${namespace}.svc/api/v1/push"
        }
        external_labels = {
          cluster = "${cluster_name}",
        }
      }

      loki.source.kubernetes "pods" {
        targets    = discovery.kubernetes.pods.targets
        forward_to = [loki.write.loki.receiver]
      }

      loki.write "loki" {
        endpoint {
          url = "http://loki-gateway.${namespace}.svc/loki/api/v1/push"
        }
        external_labels = {
          cluster = "${cluster_name}",
        }
      }

      otelcol.receiver.otlp "default" {
        grpc {
          endpoint = "0.0.0.0:4317"
        }
        http {
          endpoint = "0.0.0.0:4318"
        }
        output {
          traces = [otelcol.exporter.otlp.tempo.input]
        }
      }

      otelcol.exporter.otlp "tempo" {
        client {
          endpoint = "tempo.${namespace}.svc:4317"
          tls {
            insecure = true
          }
        }
      }
