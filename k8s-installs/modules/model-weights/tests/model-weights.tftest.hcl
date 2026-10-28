mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  config_file = "tests/fixtures/model-weights.llama-3-1-8b.yaml"
}

override_data {
  target = module.cluster.data.terraform_remote_state.core_platform
  values = {
    outputs = {
      clusters = {
        "1" = {
          cluster_name                       = "research-sandbox-euw1-1-eks"
          cluster_endpoint                   = "https://ABC.gr7.eu-west-1.eks.amazonaws.com"
          cluster_certificate_authority_data = "Q0EtREFUQQ=="
        }
      }
    }
  }
}

# Not used here; the cluster module reads it for every component.
override_data {
  target = module.cluster.data.terraform_remote_state.dns
  values = { outputs = {} }
}

override_data {
  target = data.terraform_remote_state.model_store
  values = {
    outputs = {
      bucket_name     = "research-shared-euw1-model-weights-111111111111"
      writer_role_arn = "arn:aws:iam::111111111111:role/research-shared-euw1-model-weights-writer"
    }
  }
}

run "plans_with_defaults" {
  command = plan

  assert {
    condition = (
      yamldecode(helm_release.this[0].values[0]).source.type == "huggingface" &&
      yamldecode(helm_release.this[0].values[0]).source.uri == "meta-llama/Llama-3.1-8B-Instruct" &&
      yamldecode(helm_release.this[0].values[0]).version == "0123456789abcdef0123456789abcdef01234567"
    )
    error_message = "the job fetches the pinned source and revision"
  }
  assert {
    condition     = output.s3_prefix == "s3://research-shared-euw1-model-weights-111111111111/llama-3-1-8b/0123456789abcdef0123456789abcdef01234567/"
    error_message = "weights land at s3://<bucket>/<model>/<version>/"
  }
  assert {
    condition     = output.cache_path == "/models/llama-3-1-8b/0123456789abcdef0123456789abcdef01234567" && output.model == "llama-3-1-8b"
    error_message = "vllm finds the weights at /models/<model>/<version>"
  }
  assert {
    condition     = output.size_gib == 200
    error_message = "vllm sizes its startup budget from the declared size"
  }
  assert {
    condition     = !strcontains(helm_release.this[0].values[0], "nvidia.com/gpu") && !strcontains(helm_release.this[0].values[0], "neuron") && !strcontains(helm_release.this[0].values[0], "phoenix/gpu")
    error_message = "the copy runs on CPU nodes, never a GPU pool"
  }
  assert {
    condition     = helm_release.this[0].wait_for_jobs == true && helm_release.this[0].timeout == 21600
    error_message = "state exists only after a successful copy"
  }
  assert {
    condition     = aws_eks_pod_identity_association.this[0].role_arn == "arn:aws:iam::111111111111:role/research-shared-euw1-model-weights-writer" && aws_eks_pod_identity_association.this[0].namespace == "models"
    error_message = "the job's service account uses model-store's writer role"
  }
}

run "s3_source" {
  command = plan

  variables {
    config_file = "tests/fixtures/model-weights.inhouse.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).source.type == "s3" && yamldecode(helm_release.this[0].values[0]).source.uri == "s3://acme-research-models/inhouse-7b/"
    error_message = "an s3 source syncs from its prefix"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).credentialsSecret == ""
    error_message = "an s3 source reads with the copy role, never a token"
  }
}

run "https_source" {
  command = plan

  variables {
    config_file = "tests/fixtures/model-weights.mirror.yaml"
  }

  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).source.type == "https" && yamldecode(helm_release.this[0].values[0]).sha256 == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "an https download is verified against its sha256"
  }
  assert {
    condition     = yamldecode(helm_release.this[0].values[0]).credentialsSecret == "acme/research-sandbox/models/mirror-source"
    error_message = "https credentials come from <organisation>/<env_id>/models/<instance>-source"
  }
}

run "versions_are_separate_paths" {
  command = plan

  variables {
    config_file = "tests/fixtures/model-weights.llama-3-1-8b-next.yaml"
  }

  assert {
    condition     = output.s3_prefix == "s3://research-shared-euw1-model-weights-111111111111/llama-3-1-8b/fedcba9876543210fedcba9876543210fedcba98/"
    error_message = "a new version is a new prefix of the same model"
  }
  assert {
    condition     = helm_release.this[0].name == "weights-llama-3-1-8b-fedcba9"
    error_message = "release weights-<model>-<version, first 7>, so the other version's release is untouched"
  }
}

run "first_version_release_name" {
  command = plan

  assert {
    condition     = helm_release.this[0].name == "weights-llama-3-1-8b-0123456"
    error_message = "release weights-<model>-<version, first 7>"
  }
}

run "bad_source_rejected_s3" {
  command = plan
  variables {
    config_file = "tests/fixtures/model-weights.bad-s3.yaml"
  }
  expect_failures = [terraform_data.validation]
}

run "bad_source_rejected_http" {
  command = plan
  variables {
    config_file = "tests/fixtures/model-weights.bad-http.yaml"
  }
  expect_failures = [terraform_data.validation]
}

run "bad_source_rejected_https_without_sha256" {
  command = plan
  variables {
    config_file = "tests/fixtures/model-weights.no-sha.yaml"
  }
  expect_failures = [terraform_data.validation]
}

run "bad_source_rejected_hf_branch" {
  command = plan
  variables {
    config_file = "tests/fixtures/model-weights.hf-main.yaml"
  }
  expect_failures = [terraform_data.validation]
}

run "missing_model_store_rejected" {
  command = plan

  override_data {
    target = data.terraform_remote_state.model_store
    values = { outputs = {} }
  }

  expect_failures = [terraform_data.validation]
}

run "disabled_plans_nothing" {
  command = plan

  variables {
    config_file = "tests/fixtures/model-weights.off.yaml"
  }

  assert {
    condition     = length(helm_release.this) + length(aws_eks_pod_identity_association.this) == 0
    error_message = "spec.enabled: false installs nothing"
  }
}
