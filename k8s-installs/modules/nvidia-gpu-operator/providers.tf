provider "aws" {
  region                      = local.region
  allowed_account_ids         = module.context.floci ? null : [local.account_id]
  skip_credentials_validation = module.context.floci
  skip_requesting_account_id  = module.context.floci
  skip_metadata_api_check     = module.context.floci
  dynamic "assume_role" {
    for_each = module.context.floci ? [] : [module.context.deploy_role_arn]
    content { role_arn = assume_role.value }
  }

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
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region, "--output", "json", "--role-arn", module.context.deploy_role_arn]
    }
  }
}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", local.region, "--output", "json", "--role-arn", module.context.deploy_role_arn]
  }
}
