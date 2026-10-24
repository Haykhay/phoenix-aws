# Component boilerplate

Not a module. Every component under `modules/` starts with these four files,
copied verbatim; only `resource_set` in `_context.tf` changes (the module's
directory name). Do not add `variables` beyond these two.

## `_context.tf`

```hcl
variable "config_file" {
  description = "Path to this unit's YAML (k8s-installs/environments/<tier>/<env_id>/<region>/<cluster>/<component>[.<instance>].yaml)."
  type        = string
}

variable "pipeline_user" {
  description = "Who ran the pipeline (GITHUB_ACTOR)."
  type        = string
  default     = "unknown"
}

module "context" {
  source = "../../../infrastructure/modules/context"

  config_file   = var.config_file
  resource_set  = "COMPONENT"
  pipeline_user = var.pipeline_user
}

module "cluster" {
  source = "../cluster"

  state    = module.context.state
  env_id   = module.context.env_id
  region   = module.context.region
  cluster  = module.context.config.cluster
  dns_zone = try(module.context.config.dns_zone, "zone-1")
}

locals {
  environment  = module.context.env_id
  region       = module.context.region
  account_id   = module.context.account_id
  organisation = module.context.organisation
  cluster_key  = tostring(module.context.config.cluster)
  # <component>.<instance>.yaml -> instance; singletons have none.
  instance     = try(regex("^[^.]+\\.(.+)\\.yaml$", basename(var.config_file))[0], null)
  # Cluster- and instance-unique: vision-sandbox-jdoe-euw1-1[-llama-3-8b]
  name_prefix  = join("-", compact([module.context.name_prefix, local.cluster_key, local.instance]))
  cluster_name = module.cluster.cluster_name
}
```

## `providers.tf`

```hcl
provider "aws" {
  region              = local.region
  allowed_account_ids = [local.account_id]

  default_tags {
    tags = merge(
      module.context.tags,
      { Cluster = local.cluster_key },
      local.instance == null ? {} : { Instance = local.instance },
    )
  }
}

# A fresh EKS token per call (aws eks get-token): a token fetched once per
# run expires after 15 minutes, and Helm waits can be longer (vLLM: 30).
# The runner needs the aws CLI.
provider "helm" {
  kubernetes = {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region, "--output", "json"]
    }
  }
}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region, "--output", "json"]
  }
}
```

## `backend.tf`

```hcl
# Partial: the workflow supplies bucket, key, region, encrypt, use_lockfile.
terraform {
  backend "s3" {}
}
```

## `versions.tf`

```hcl
terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

## Tests

`tests/<component>.tftest.hcl` mocks aws, helm and kubernetes and overrides
`module.cluster.data.terraform_remote_state.core_platform` / `.dns`. Every
module has at least `plans_with_defaults` and `disabled_plans_nothing`.
