# Read by k8s-installs aws-fsx-csi-driver to bind a static, read-only volume.

output "file_system_id" {
  description = "FSx for Lustre file system ID (the CSI volume handle)."
  value       = aws_fsx_lustre_file_system.this.id
}

output "dns_name" {
  description = "File system DNS name (CSI volumeAttributes.dnsname)."
  value       = aws_fsx_lustre_file_system.this.dns_name
}

output "mount_name" {
  description = "Lustre mount name (CSI volumeAttributes.mountname)."
  value       = aws_fsx_lustre_file_system.this.mount_name
}

output "weights_path_prefix" {
  description = "Where the weights bucket appears inside the file system: <prefix>/<model>/<version>/."
  value       = local.weights_path_prefix
}

output "resource_summary" {
  value = {
    environment  = local.environment
    region       = local.region
    resource_set = "model-cache"
    cluster      = local.cluster_key
    capacity_gib = local.config.storage_capacity_gib
    long_live    = local.long_live
  }
}
