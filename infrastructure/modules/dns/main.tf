# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline, and tag churn rolls cluster nodes.
resource "terraform_data" "created_by" {
  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

# --- Public zones ---

resource "aws_route53_zone" "public" {
  for_each = local.zones_public_create
  name     = each.value.public_zone_name

  tags = local.ownership_tags[each.key]
}

data "aws_route53_zone" "public" {
  for_each     = local.zones_public_adopt
  name         = each.value.public_zone_name
  private_zone = false
}

# --- Internal zones ---

resource "aws_route53_zone" "internal" {
  for_each = local.zones_internal_create
  name     = each.value.internal_zone_name

  tags = local.ownership_tags[each.key]
}

data "aws_route53_zone" "internal" {
  for_each     = local.zones_internal_adopt
  name         = each.value.internal_zone_name
  private_zone = false
}

resource "aws_route53_record" "internal_ns" {
  for_each        = local.zones_internal_ns
  zone_id         = local.zone_ids[each.key].public
  name            = each.value.internal_zone_name
  type            = "NS"
  ttl             = 300
  records         = local.zone_name_servers[each.key].internal
  allow_overwrite = true
}
