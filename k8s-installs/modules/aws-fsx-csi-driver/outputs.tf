output "pvc_name" {
  description = "Read-only claim on the model cache, in namespace models."
  value       = local.pvc_name
}

output "mount_path" {
  description = "Where model servers mount the claim: weights are at <mount_path>/<model>/<version>."
  value       = "/models"
}

output "sub_path" {
  description = "Claim subPath to mount at mount_path: the weights bucket's directory inside the file system."
  value       = "weights"
}

output "resource_summary" {
  value = {
    environment    = local.environment
    region         = local.region
    cluster        = local.cluster_key
    resource_set   = "aws-fsx-csi-driver"
    chart_version  = try(helm_release.driver[0].version, null)
    file_system_id = try(local.cache.file_system_id, null)
  }
}
