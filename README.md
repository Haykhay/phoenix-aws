# Phoenix on AWS

Self-service infrastructure for normal applications and AI workloads. A
developer, engineer or researcher asks Backstage for what they need — an
environment, then a workload type, a database, a GPU, a model — and gets it:
Backstage writes one YAML file per unit into this repo, and one GitHub Actions
workflow runs plain Terraform for each, in order.

![Architecture](infrastructure/docs/architecture/phoenix-architecture.png)

| Folder | What | |
|---|---|---|
| [`infrastructure/`](infrastructure/README.md) | Layer 2 — the AWS side of an environment: VPCs (IPAM), EKS, data services, DNS, observability storage, ECR pull-through | 9 resource sets |
| [`k8s-installs/`](k8s-installs/README.md) | Layer 3 — what runs inside each cluster: baseline, gateway, delivery, databases, GPUs, vLLM, Langfuse | 25 components |
| Backstage (separate: it fronts every cloud in the series) | The front door: the environment and workload forms, the catalog of what's on offer, Entra sign-in (toggle) | runs locally in Docker |
| [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) | The one pipeline for both layers | |
| [`docs/adr/`](docs/adr/README.md) | The architecture decisions behind it, one record each | 10 ADRs |

## How a request flows

1. **Environment form** → `infrastructure/environments/<tier>/<env_id>/<scope>/<resource-set>.yaml`
   (network, cluster, DNS, data services) and a cluster entity for the catalog.
2. **Workload form** → `k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/<component>[.<instance>].yaml`,
   one per component the chosen options need. Versions and sizes are the
   platform's, never the form's.
3. **Workflow** → checks each file's path against its contents, assumes
   `arn:aws:iam::<account_id>:role/Terraform-Role`, and plans (pull requests)
   or applies/destroys (dispatched by Backstage from `main`). Cluster units run
   on a self-hosted runner in the management VPC; EKS endpoints are private.

## Status

**Designed and verified offline; not yet applied to a real AWS account.**
Verification so far:

- `terraform test` for every Terraform root, against mock providers: 44 tests
  in `infrastructure`, 94 in `k8s-installs`.
- Every chart rendered with real `helm template`; custom resources validated
  with `kubeconform -strict` against published or vendored schemas.
- The Backstage forms dry-run through Backstage's own API, and every file they
  generate passes the workflow's path checks and a `terraform plan`.
- The workflow's own steps tested against path and pull-request cases;
  `actionlint` clean.

Still to build before going live: account vending (StackSets, account
registry), the networking foundation (IPAM pools, transit gateway, management
VPC), and the orchestrator that runs units in order and notifies the
requester. Before the pipeline is connected to AWS, pull-request plans move to
a read-only `Terraform-Plan-Role` (apply/destroy keep `Terraform-Role`, trusted
only from `main`), and the self-hosted runner is registered as described in
[`k8s-installs/README.md`](k8s-installs/README.md#how-it-runs). Images will be routed through each account's ECR pull-through
cache once the tooling account exists.

## Running the tests

Terraform ≥ 1.15:

```bash
cd infrastructure/modules/<resource-set>   # or k8s-installs/modules/<component>
terraform init -backend=false && terraform test
```

Backstage lives in its own repository, next to the cloud repositories, because
it fronts all of them.
