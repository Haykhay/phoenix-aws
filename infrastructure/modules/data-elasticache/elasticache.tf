# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline, and tag churn rolls cluster nodes.
resource "terraform_data" "elasticache_clusters_created_by" {
  for_each = local.elasticache_clusters

  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_kms_key" "elasticache" {
  for_each = local.elasticache_clusters

  description = "${local.name_prefix}-${each.value.base_name_postfix} encryption key"
  tags        = local.elasticache_clusters_ownership_tags[each.key]
}

resource "aws_security_group" "elasticache" {
  for_each = local.elasticache_clusters

  name        = "${local.name_prefix}-${each.value.base_name_postfix}"
  description = "Security Group for ElastiCache managed by Terraform"
  vpc_id      = try(local.cluster_networks[each.key].vpc_id, null)

  tags = merge(local.elasticache_clusters_ownership_tags[each.key], {
    Name = "${local.name_prefix}-${each.value.base_name_postfix}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "elasticache_cidr" {
  for_each = {
    for rule in flatten([
      for cluster_name, cluster in local.elasticache_clusters : [
        for cidr in local.allowed_cidr_blocks : {
          key          = "${cluster_name}/${cidr}"
          cluster_name = cluster_name
          port         = try(local.config.port, 6379)
          cidr         = cidr
        }
      ]
    ]) : rule.key => rule
  }

  security_group_id = aws_security_group.elasticache[each.value.cluster_name].id
  description       = "Allow ElastiCache access from ${each.value.cidr}"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "elasticache_sg" {
  for_each = {
    for rule in flatten([
      for cluster_name, cluster in local.elasticache_clusters : [
        for security_group_id in local.allowed_security_group_ids[cluster_name] : {
          key               = "${cluster_name}/${security_group_id}"
          cluster_name      = cluster_name
          port              = try(local.config.port, 6379)
          security_group_id = security_group_id
        }
      ]
    ]) : rule.key => rule
  }

  security_group_id            = aws_security_group.elasticache[each.value.cluster_name].id
  description                  = "Allow ElastiCache access from security group ${each.value.security_group_id}"
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value.security_group_id
}

module "credentials" {
  source = "../credentials"

  organisation = local.organisation

  credentials = {
    for name, cluster in local.elasticache_clusters : name => {
      policy  = "elasticache_auth"
      keepers = try(cluster.password_keepers, null)
    } if cluster.transit_encryption
  }
}

module "elasticache" {
  for_each = local.elasticache_clusters

  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.11.0"

  # Over 40 characters terraform_data.validation fails the plan with a message
  # naming the limit; the cut here only stops the provider's own length check
  # from pre-empting it. A plan that fails never reaches AWS.
  replication_group_id = replace(substr("${local.name_prefix}-${each.value.base_name_postfix}", 0, 40), "/-+$/", "")
  description          = coalesce(try(each.value.description, null), "${local.name_prefix}-${each.value.base_name_postfix} replication group")

  create_replication_group = true
  create_cluster           = false
  create_security_group    = false

  engine         = each.value.engine
  engine_version = each.value.engine_version
  node_type      = each.value.node_type
  port           = try(local.config.port, 6379)

  num_cache_clusters         = each.value.num_cache_clusters
  automatic_failover_enabled = each.value.automatic_failover
  multi_az_enabled           = each.value.multi_az
  apply_immediately          = each.value.apply_immediately

  create_subnet_group = true
  subnet_ids          = local.cluster_subnet_ids[each.key]
  security_group_ids  = [aws_security_group.elasticache[each.key].id]

  at_rest_encryption_enabled = each.value.at_rest_encryption
  transit_encryption_enabled = each.value.transit_encryption
  kms_key_arn                = each.value.at_rest_encryption ? aws_kms_key.elasticache[each.key].arn : null
  auth_token                 = each.value.transit_encryption ? module.credentials.passwords[each.key] : null

  snapshot_retention_limit = each.value.snapshot_retention_limit

  tags = local.elasticache_clusters_ownership_tags[each.key]
}

module "elasticache_secrets_manager" {
  for_each = local.elasticache_clusters

  source      = "terraform-aws-modules/secrets-manager/aws"
  version     = "1.1.2"
  name_prefix = "${local.name_prefix}-${each.value.base_name_postfix}-cache-credentials"
  description = "ElastiCache credentials"

  kms_key_id = aws_kms_key.elasticache[each.key].arn

  secret_string = jsonencode({
    primary_endpoint = module.elasticache[each.key].replication_group_primary_endpoint_address
    reader_endpoint  = module.elasticache[each.key].replication_group_reader_endpoint_address
    port             = module.elasticache[each.key].replication_group_port
    auth_token       = each.value.transit_encryption ? module.credentials.passwords[each.key] : null
  })

  tags = local.elasticache_clusters_ownership_tags[each.key]
}
