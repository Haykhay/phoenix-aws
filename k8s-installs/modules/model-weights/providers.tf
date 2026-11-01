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
