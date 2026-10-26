locals {
  # Regions that have joined, from the YAML. Backstage appends a region when
  # its first environment is requested; one is never removed (its pool CIDRs
  # are prevent_destroy).
  regions  = toset(local.spec.regions)
  segments = local.network.segments

  regional_pools = {
    for pair in setproduct(local.regions, keys(local.segments)) :
    "${pair[0]}/${pair[1]}" => { region = pair[0], segment = pair[1] }
  }
}
