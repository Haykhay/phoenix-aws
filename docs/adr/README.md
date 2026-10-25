# Architecture decision records

Decisions behind Phoenix on AWS, one file each. Status: all **Accepted** (2026-10-25) unless noted.

| # | Decision |
|---|---|
| [0001](0001-self-service-through-backstage-delivered-by-plain-terraform.md) | Self-service through Backstage, delivered by plain Terraform |
| [0002](0002-one-aws-account-per-group-deploy-roles-known-by-name.md) | One AWS account per group; deploy roles known by name |
| [0003](0003-two-layers-one-repository-one-workflow.md) | Two layers, one repository, one workflow |
| [0004](0004-the-developer-chooses-the-kind-of-thing-the-platform-chooses-the-rest.md) | The developer chooses the kind of thing; the platform chooses the rest |
| [0005](0005-self-hosted-observability-per-cluster-history-in-the-groups-bucket.md) | Self-hosted observability per cluster, history in the group's bucket |
| [0006](0006-images-through-ecr-a-central-hub-and-a-pull-through-cache-per-account.md) | Images through ECR: a central hub and a pull-through cache per account |
| [0007](0007-secrets-live-under-the-environments-prefix-only.md) | Secrets live under the environment's prefix only |
| [0008](0008-istio-as-the-one-gateway-with-the-inference-extension-for-models.md) | Istio as the one gateway, with the Inference Extension for models |
| [0009](0009-verify-offline-before-deploying.md) | Verify offline before deploying |
| [0010](0010-teardown-is-a-normal-operation.md) | Teardown is a normal operation |
