{{/* Pod spec of one llm-d server set; .worker for LeaderWorkerSet workers. */}}
{{- define "vllm.llmdPod" -}}
{{- $v := .v }}{{- $set := .set }}
nodeSelector:
  phoenix/gpu: {{ $v.gpu.type | quote }}
tolerations:
  - key: {{ $v.accelerator.taint }}
    operator: Exists
    effect: NoSchedule
{{- if and $set.sidecar (not .worker) }}
initContainers:
  # P/D: receives the request, has prefill run it, then hands it to decode.
  - name: routing-proxy
    image: {{ $v.llmD.sidecarImage }}
    args: ["--port=8000", "--kv-connector=nixlv2", "--zap-log-level=1", "--secure-proxy=false"]
    ports:
      - { name: sidecar, containerPort: 8000 }
    restartPolicy: Always
    securityContext: { allowPrivilegeEscalation: false, runAsNonRoot: true }
{{- end }}
containers:
  - name: vllm
    image: "{{ $v.image.repository }}:{{ $v.image.tag }}"
    command: ["/bin/sh", "-c"]
    args:
      - exec vllm serve {{ join " " $set.args }}{{ if .worker }} --headless{{ end }}
    env:
      - { name: HF_HUB_OFFLINE, value: "1" }
      {{- with $v.llmD.kvTransferConfig }}
      - { name: KV_TRANSFER_CONFIG, value: {{ . | quote }} }
      - name: VLLM_NIXL_SIDE_CHANNEL_HOST
        valueFrom: { fieldRef: { fieldPath: status.podIP } }
      {{- end }}
      {{- if $v.llmD.efa.enabled }}
      - { name: FI_PROVIDER, value: efa }
      {{- end }}
    ports:
      - { name: http, containerPort: {{ $set.port }} }
    resources:
      {{- with $v.llmD.memoryRequest }}
      requests:
        memory: {{ . }}
      {{- end }}
      limits:
        {{ $v.accelerator.resource }}: {{ $v.gpu.perReplica }}
        {{- if $v.llmD.efa.enabled }}
        vpc.amazonaws.com/efa: {{ $v.llmD.efa.interfaces }}
        {{- end }}
    {{- if $v.llmD.efa.enabled }}
    securityContext:
      capabilities: { add: [IPC_LOCK] }
    {{- end }}
    {{- if not .worker }}
    readinessProbe:
      httpGet: { path: /health, port: {{ $set.port }} }
      periodSeconds: 10
      failureThreshold: 3
    startupProbe:
      httpGet: { path: /health, port: {{ $set.port }} }
      periodSeconds: 10
      failureThreshold: {{ div $v.startupSeconds 10 }}
    {{- end }}
    volumeMounts:
      - name: weights
        mountPath: {{ $v.cache.mountPath }}
        subPath: {{ $v.cache.subPath }}
        readOnly: true
      - { name: shm, mountPath: /dev/shm }
volumes:
  - name: weights
    persistentVolumeClaim: { claimName: {{ $v.cache.claim }}, readOnly: true }
  - name: shm
    emptyDir: { medium: Memory, sizeLimit: 64Gi }
{{- end }}

{{/* Pod labels: the pool selects app; P/D sets carry llm-d.ai/role. Workers are not endpoints. */}}
{{- define "vllm.llmdMeta" -}}
labels:
  app: {{ if .worker }}{{ .v.name }}-worker{{ else }}{{ .v.name }}{{ end }}
  phoenix/set: {{ .set.name }}
  {{- with .set.role }}
  llm-d.ai/role: {{ . }}
  {{- end }}
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: {{ .set.port | quote }}
{{- end }}
