# ADR-0008: Istio as the one gateway, with the Inference Extension for models

Status: Accepted · 2026-10-25

## Context

Normal services need ingress, DNS and certificates; served models need routing that understands model servers' load.

## Decision

**Istio** is the cluster's single **Gateway API** implementation, behind NLBs from the AWS Load Balancer Controller, with cert-manager wildcard certificates on the cluster's zones. Models are served by **vLLM**, one unit per model, behind an **`InferencePool`** with its endpoint picker (Gateway API Inference Extension), so requests go to the replica with capacity.

## Consequences

- Istio needs cert-manager and the load balancer controller first; cert-manager's own Gateway API integration is off to avoid a dependency cycle.
- The Inference Extension chart and endpoint picker are pinned to the newest release the Kubernetes registry publishes.
