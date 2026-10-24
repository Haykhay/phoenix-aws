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

# --- NS delegation: public zone into parent (cross-account via aws.management) ---
# Only needed when the public zone is a subdomain of an externally-owned parent
# (e.g. sandbox.example.com → example.com). Not used for apex domains like example-cx.com.

data "aws_route53_zone" "parent" {
  for_each     = local.zones_delegate
  provider     = aws.management
  name         = each.value.parent_zone_name
  private_zone = false
}

resource "aws_route53_record" "public_ns" {
  for_each        = local.zones_delegate
  provider        = aws.management
  zone_id         = data.aws_route53_zone.parent[each.key].zone_id
  name            = each.value.public_zone_name
  type            = "NS"
  ttl             = 300
  records         = local.zone_name_servers[each.key].public
  allow_overwrite = true
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
