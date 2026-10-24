# CreatedBy is captured once and frozen: read every run it would record
# whoever last triggered a pipeline, and tag churn rolls cluster nodes.
resource "terraform_data" "created_by" {
  for_each = local.clusters

  input = var.pipeline_user

  lifecycle {
    ignore_changes = [input]
  }
}

resource "aws_kms_key" "msk" {
  for_each    = local.clusters
  description = "${each.value.name_prefix} MSK encryption key"

  tags = local.ownership_tags[each.key]
}

resource "aws_kms_key_policy" "msk" {
  for_each = local.clusters
  key_id   = aws_kms_key.msk[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # CloudWatch Logs requires an explicit key policy grant — account root kms:* is not sufficient
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

# ------------------------------------------------
# Security group (KRaft/IAM-only: ports 9094 TLS + 9098 SASL/IAM)
# ------------------------------------------------

resource "aws_security_group" "msk" {
  for_each    = local.clusters
  name        = "${each.value.name_prefix}-msk"
  description = "MSK cluster security group"
  vpc_id      = try(local.cluster_networks[each.key].vpc_id, null)

  tags = local.ownership_tags[each.key]
}

locals {
  msk_ports = {
    tls      = 9094
    sasl_iam = 9098
  }
}

resource "aws_vpc_security_group_ingress_rule" "msk_cidr" {
  for_each = {
    for rule in flatten([
      for cluster_key, cluster in local.clusters : [
        for port_name, port in local.msk_ports : [
          for cidr in distinct(cluster.allowed_cidr_blocks) : {
            key         = "${cluster_key}/${port_name}/${cidr}"
            cluster_key = cluster_key
            port        = port
            cidr        = cidr
          }
        ]
      ]
    ]) : rule.key => rule
  }

  security_group_id = aws_security_group.msk[each.value.cluster_key].id
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_ingress_rule" "msk_sg" {
  for_each = {
    for rule in flatten([
      for cluster_key, sg_ids in local.cluster_node_security_group_ids : [
        for port_name, port in local.msk_ports : [
          for sg_id in sg_ids : {
            key         = "${cluster_key}/${port_name}/${sg_id}"
            cluster_key = cluster_key
            port        = port
            sg_id       = sg_id
          }
        ]
      ]
    ]) : rule.key => rule
  }

  security_group_id            = aws_security_group.msk[each.value.cluster_key].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.sg_id
}

resource "aws_vpc_security_group_egress_rule" "msk" {
  for_each          = local.clusters
  security_group_id = aws_security_group.msk[each.key].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ------------------------------------------------
# MSK cluster (community module)
# ------------------------------------------------

module "msk" {
  for_each = local.clusters
  source   = "terraform-aws-modules/msk-kafka-cluster/aws"
  version  = "2.13.1"

  depends_on = [aws_kms_key_policy.msk]

  name          = each.value.name_prefix
  kafka_version = each.value.kafka_version

  number_of_broker_nodes      = each.value.broker_per_zone * length(local.cluster_subnet_ids[each.key])
  broker_node_instance_type   = each.value.broker_instance_type
  broker_node_client_subnets  = local.cluster_subnet_ids[each.key]
  broker_node_security_groups = [aws_security_group.msk[each.key].id]

  encryption_in_transit_client_broker = "TLS"
  encryption_in_transit_in_cluster    = true
  encryption_at_rest_kms_key_arn      = aws_kms_key.msk[each.key].arn

  client_authentication = {
    sasl = {
      iam = true
      # Switched on only for clusters that declare scram_users, so no cluster
      # gains an auth mode nobody asked for.
      scram = length(each.value.scram_users) > 0
    }
  }

  configuration_server_properties = {
    "log.message.timestamp.type" = "LogAppendTime"
  }

  cloudwatch_logs_enabled                = true
  cloudwatch_log_group_kms_key_id        = aws_kms_key.msk[each.key].arn
  cloudwatch_log_group_retention_in_days = try(each.value.cloudwatch_log_retention_days, 7)

  tags = local.ownership_tags[each.key]
}

# ------------------------------------------------
# SASL/SCRAM credentials
# ------------------------------------------------

# Generated by the shared module. AWS imposes two rules on SCRAM
# secrets that the module encodes: the name must begin with "AmazonMSK_", and
# the secret must be encrypted with a customer-managed key, an association
# whose secret uses the default aws/secretsmanager key is rejected.
module "scram_credentials" {
  source = "../credentials"

  organisation = local.organisation

  credentials = {
    for key, credential in local.scram_credentials : key => {
      policy   = "msk_scram"
      username = credential.username
    }
  }

  publish = {
    for key, credential in local.scram_credentials : key => {
      environment = local.environment
      service     = "kafka"
      binding     = "managed"
      instance    = replace(key, "/", "_")

      kms_key_arn = aws_kms_key.msk[credential.cluster_key].arn
      description = "MSK SASL/SCRAM credentials for ${credential.username} on ${local.clusters[credential.cluster_key].name_prefix}"

      # Deliberately empty: MSK requires the secret to hold exactly the keys
      # username and password, and rejects anything else.
      payload = {}

      tags = local.ownership_tags[credential.cluster_key]
    }
  }
}

resource "aws_msk_scram_secret_association" "this" {
  for_each = local.scram_clusters

  cluster_arn = module.msk[each.key].arn

  secret_arn_list = [
    for key, credential in local.scram_credentials :
    module.scram_credentials.secret_arns[key] if credential.cluster_key == each.key
  ]
}

# ------------------------------------------------
# IAM cluster resource policy (users + ACLs)
# ------------------------------------------------

resource "aws_msk_cluster_policy" "this" {
  for_each    = local.policy_clusters
  cluster_arn = module.msk[each.key].arn
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.cluster_policy_statements[each.key]
  })
}

# ------------------------------------------------
# Connection info secret (bootstrap brokers)
# ------------------------------------------------

resource "aws_secretsmanager_secret" "msk" {
  for_each                = local.clusters
  name                    = "${each.value.name_prefix}-msk"
  kms_key_id              = aws_kms_key.msk[each.key].arn
  recovery_window_in_days = 0

  tags = local.ownership_tags[each.key]
}

resource "aws_secretsmanager_secret_version" "msk" {
  for_each  = local.clusters
  secret_id = aws_secretsmanager_secret.msk[each.key].id
  secret_string = jsonencode({
    bootstrap_brokers_sasl_iam = module.msk[each.key].bootstrap_brokers_sasl_iam
  })
}
