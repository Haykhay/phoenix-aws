# model-store owns the writer role (list, read, write, never delete); this
# unit only binds the job's service account to it.
resource "aws_eks_pod_identity_association" "this" {
  count           = local.config.enabled ? 1 : 0
  cluster_name    = local.cluster_name
  namespace       = local.namespace
  service_account = local.release
  role_arn        = local.store.writer_role_arn

  depends_on = [terraform_data.validation]
}

# Same buffer as external-dns: injection happens only at admission, so a job
# pod created before the association is live stays unauthorized for good.
resource "time_sleep" "pod_identity_propagation" {
  count           = local.config.enabled ? 1 : 0
  depends_on      = [aws_eks_pod_identity_association.this]
  create_duration = "20s"
}
