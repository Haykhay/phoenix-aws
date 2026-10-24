# istio

Istio (charts `base` + `istiod` `1.30.1`, pinned) as the cluster's one
[Gateway API](https://gateway-api.sigs.k8s.io) implementation — for normal
services and for model serving. Part of both the **service** and
**model-serving** sets.

| Release | What |
|---|---|
| `gateway-api-crds` | Gateway API standard CRDs v1.5.1 + Inference Extension v1.6.2 `InferencePool` (vendored; the latter checked against the release asset's sha256) |
| `istio-base`, `istiod` | istiod with `ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true`, so HTTPRoutes can target an `InferencePool` (vLLM) |
| `istio-extras` | Gateways `istio-internal` (always) and `istio-external` (`spec.settings.gateways.external.enabled: true`), each with a cert-manager wildcard certificate on the cluster's internal / public zone |

Each gateway gets an NLB from aws-load-balancer-controller (IP targets;
`internal` or `internet-facing`). Output `gateways` gives HTTPRoutes their
`parentRefs` and domain.

Needs, applied first: cert-manager (certificates), aws-load-balancer-controller
(NLBs), and the environment's dns unit (zones). The CRDs are not
`prevent_destroy`: a weekend teardown removes this unit after everything that
uses them.
