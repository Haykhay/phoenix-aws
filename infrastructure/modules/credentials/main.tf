resource "random_password" "this" {
  for_each = local.resolved

  length           = each.value.length
  special          = each.value.special
  override_special = each.value.override_special

  min_special = each.value.min_special
  min_upper   = each.value.min_upper
  min_lower   = each.value.min_lower
  min_numeric = each.value.min_numeric

  keepers = each.value.keepers

  # Deliberately no ignore_changes anywhere in this module. Suppressing the
  # diff would let the code claim one policy while the state holds another,
  # which is exactly the drift this module exists to remove.
}

resource "aws_secretsmanager_secret" "this" {
  for_each = var.publish

  name        = local.secret_names[each.key]
  description = coalesce(each.value.description, "${var.organisation} ${each.value.binding} binding for ${each.value.service}")

  # MSK refuses to associate a SCRAM secret encrypted with the AWS-managed
  # key, so a customer-managed key is mandatory for that policy.
  kms_key_id = each.value.kms_key_arn

  recovery_window_in_days = each.value.recovery_window_in_days

  tags = each.value.tags

  lifecycle {
    precondition {
      condition     = var.credentials[each.key].policy != "msk_scram" || each.value.kms_key_arn != null
      error_message = "MSK SASL/SCRAM secrets must be encrypted with a customer-managed KMS key; AWS rejects an association whose secret uses the default aws/secretsmanager key. Set kms_key_arn for credential \"${each.key}\"."
    }
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = var.publish

  secret_id = aws_secretsmanager_secret.this[each.key].id

  # payload carries the connection details, which generally depend on the
  # backing resource. Only these two fields come from the module itself.
  secret_string = jsonencode(merge(
    each.value.payload,
    {
      username = var.credentials[each.key].username
      password = random_password.this[each.key].result
    },
  ))

  lifecycle {
    precondition {
      condition     = var.credentials[each.key].policy != "msk_scram" || length(each.value.payload) == 0
      error_message = "An MSK SASL/SCRAM secret must hold exactly the keys username and password; AWS rejects an association whose secret carries anything else. Remove the payload from credential \"${each.key}\"."
    }

    precondition {
      condition     = var.credentials[each.key].policy != "msk_scram" || var.credentials[each.key].username != null
      error_message = "An MSK SASL/SCRAM credential needs a username — it becomes the SCRAM identity. Set username on credential \"${each.key}\"."
    }
  }
}
