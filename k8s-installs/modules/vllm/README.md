# vllm

One served model per unit: `vllm.<model slug>.yaml` (e.g.
`vllm.llama-3-8b.yaml`). Part of the **model-serving** set; Backstage writes
one per chosen model, with the platform's values from the `phoenix-model`
catalog entity.

| `spec` | Default | |
|---|---|---|
| `model` | **required** | Hugging Face ID, e.g. `meta-llama/Llama-3.1-8B-Instruct` |
| `gpu` | **required** | GPU type; its `karpenter-nodepool.<gpu>` unit must exist |
| `replicas` | `1` | |
| `gpus_per_replica` | `1` | tensor parallelism |
| `max_model_len`, `extra_args` | none | passed to vLLM |
| `image_tag` | `v0.31.0` | `vllm/vllm-openai`, pinned |

What it creates, in `models`:

- **vLLM** `vllm-<slug>` on the GPU pool (`nodeSelector phoenix/gpu=<gpu>`,
  tolerates `nvidia.com/gpu`), OpenAI-compatible API on 8000; Alloy scrapes its
  metrics. Startup allows 30 minutes to download and load the model.
- **InferencePool** `vllm-<slug>-pool` with its endpoint picker (Gateway API
  Inference Extension chart `v1.5.0`, istio provider; requests trimmed to
  500m/1Gi for sandbox). The picker chooses a replica per request from
  vLLM's own load metrics.
- **HTTPRoute** on istio's internal gateway: `https://<slug>-<cluster>.<internal zone>/v1`
  (output `endpoint`), with an external-dns record.
- **Hugging Face token** (optional, for gated models) from
  `<organisation>/<env_id>/models/hf-token` (property `token`).

The plan fails clearly without the cluster's istio unit or the GPU pool unit.
