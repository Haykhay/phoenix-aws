# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline, and tag churn rolls cluster nodes.
resource "terraform_data" "instances_created_by" {
  for_each = local.instances

  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_kms_key" "rds" {
  for_each = local.instances

  description = "${local.rds_base_name}-${each.value.base_name_postfix} encryption key"
  tags        = local.instances_ownership_tags[each.key]
}

resource "aws_security_group" "rds" {
  for_each = local.instances

  name        = "${local.rds_base_name}-${each.value.base_name_postfix}"
  description = "Security Group for RDS managed by Terraform"
  vpc_id      = try(local.instance_networks[each.key].vpc_id, null)

  tags = merge(local.instances_ownership_tags[each.key], {
    Name = "${local.rds_base_name}-${each.value.base_name_postfix}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = {
    for rule in flatten([
      for instance_name, instance in local.instances : [
        for cidr in local.allowed_cidr_blocks : {
          key           = "${instance_name}/${cidr}"
          instance_name = instance_name
          port          = instance.port
          cidr          = cidr
        }
      ]
    ]) : rule.key => rule
  }

  security_group_id = aws_security_group.rds[each.value.instance_name].id
  description       = "Allow RDS access from ${each.value.cidr}"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "security_group" {
  for_each = {
    for rule in flatten([
      for instance_name, instance in local.instances : [
        for security_group_id in local.allowed_security_group_ids[instance_name] : {
          key               = "${instance_name}/${security_group_id}"
          instance_name     = instance_name
          port              = instance.port
          security_group_id = security_group_id
        }
      ]
    ]) : rule.key => rule
  }

  security_group_id            = aws_security_group.rds[each.value.instance_name].id
  description                  = "Allow RDS access from security group ${each.value.security_group_id}"
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value.security_group_id
}

module "credentials" {
  source = "../credentials"

  organisation = local.organisation

  credentials = {
    for name, instance in local.instances : name => {
      policy  = "rds_master"
      keepers = try(instance.password_keepers, null)
    }
  }
}

module "rds" {
  for_each = local.instances

  source  = "terraform-aws-modules/rds/aws"
  version = "6.9.0"

  identifier = "${local.rds_base_name}-${each.value.base_name_postfix}"
  db_name    = each.value.db_name
  username   = each.value.username

  engine                      = each.value.engine
  engine_version              = each.value.engine_version
  instance_class              = each.value.instance_class
  allocated_storage           = each.value.allocated_storage
  storage_type                = try(each.value.storage_type, "gp3")
  iops                        = try(each.value.iops, null)
  storage_throughput          = try(each.value.storage_throughput, null)
  auto_minor_version_upgrade  = each.value.auto_minor_version_upgrade
  backup_window               = each.value.backup_window
  backup_retention_period     = each.value.backup_retention_period
  storage_encrypted           = true
  kms_key_id                  = aws_kms_key.rds[each.key].arn
  subnet_ids                  = local.instance_subnet_ids[each.key]
  create_db_subnet_group      = true
  manage_master_user_password = false
  password                    = module.credentials.passwords[each.key]
  vpc_security_group_ids      = [aws_security_group.rds[each.key].id]
  create_db_option_group      = true
  major_engine_version        = each.value.major_engine_version
  apply_immediately           = each.value.apply_immediately
  create_db_parameter_group   = true
  parameter_group_name        = "${local.rds_base_name}-${each.value.base_name_postfix}"
  family                      = each.value.family
  multi_az                    = false
  parameters                  = each.value.parameters

  enabled_cloudwatch_logs_exports        = each.value.enabled_cloudwatch_logs_exports
  create_cloudwatch_log_group            = length(each.value.enabled_cloudwatch_logs_exports) > 0
  cloudwatch_log_group_retention_in_days = each.value.cloudwatch_log_group_retention_days

  tags = local.instances_ownership_tags[each.key]
}

module "rds_secrets_manager" {
  for_each = local.instances

  source      = "terraform-aws-modules/secrets-manager/aws"
  version     = "1.1.2"
  name        = "${local.secret_name_prefix}/${each.value.base_name_postfix}-${each.value.engine}-db-config"
  description = "RDS config"

  kms_key_id = aws_kms_key.rds[each.key].arn

  secret_string = jsonencode({
    endpoint = module.rds[each.key].db_instance_endpoint,
    address  = module.rds[each.key].db_instance_address,
    port     = module.rds[each.key].db_instance_port,
    username = module.rds[each.key].db_instance_username,
    password = module.credentials.passwords[each.key],
    engine   = each.value.engine,
  })

  tags = local.instances_ownership_tags[each.key]
}

module "rds_replica" {
  for_each = {
    for key, value in local.instances : key => value if value.replica_enabled
  }

  source     = "terraform-aws-modules/rds/aws"
  version    = "6.9.0"
  identifier = "${local.rds_base_name}-${each.value.base_name_postfix}-replica"

  replicate_source_db = module.rds[each.key].db_instance_identifier

  instance_class             = each.value.instance_class
  family                     = each.value.family
  engine_version             = each.value.engine_version
  major_engine_version       = each.value.major_engine_version
  storage_type               = try(each.value.storage_type, "gp3")
  iops                       = try(each.value.iops, null)
  storage_throughput         = try(each.value.storage_throughput, null)
  auto_minor_version_upgrade = each.value.auto_minor_version_upgrade
  backup_window              = each.value.backup_window
  backup_retention_period    = each.value.backup_retention_period
  storage_encrypted          = true
  kms_key_id                 = aws_kms_key.rds[each.key].arn
  subnet_ids                 = local.instance_subnet_ids[each.key]
  vpc_security_group_ids     = [aws_security_group.rds[each.key].id]

  create_db_subnet_group    = false
  create_db_option_group    = false
  create_db_parameter_group = false

  enabled_cloudwatch_logs_exports        = each.value.enabled_cloudwatch_logs_exports
  create_cloudwatch_log_group            = length(each.value.enabled_cloudwatch_logs_exports) > 0
  cloudwatch_log_group_retention_in_days = each.value.cloudwatch_log_group_retention_days

  tags = local.instances_ownership_tags[each.key]
}
