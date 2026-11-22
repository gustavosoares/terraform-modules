# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:my-app/config-AbCdEf"
      id  = "arn:aws:secretsmanager:us-east-1:111111111111:secret:my-app/config-AbCdEf"
    }
  }
}

variables {
  name = "my-app/config"
}

run "defaults" {
  assert {
    condition     = aws_secretsmanager_secret.this.recovery_window_in_days == 30 && aws_secretsmanager_secret.this.kms_key_id == null
    error_message = "Secret should use the AWS managed key and a 30-day recovery window."
  }
  assert {
    condition     = length(aws_secretsmanager_secret_version.initial) == 0 && length(aws_secretsmanager_secret_policy.this) == 0
    error_message = "No value or resource policy should be created by default."
  }
  assert {
    condition = (
      one(data.aws_iam_policy_document.read.statement).resources == toset([aws_secretsmanager_secret.this.arn]) &&
      length(data.aws_iam_policy_document.read.statement) == 1
    )
    error_message = "Read policy should cover only this secret, with no KMS statement."
  }
}

run "initial_value" {
  variables {
    initial_secret_string = "{\"api_url\":\"https://api.example.com\"}"
  }
  assert {
    condition     = length(aws_secretsmanager_secret_version.initial) == 1
    error_message = "An initial version should be created."
  }
}

# Same state as "initial_value": a new value must not overwrite the stored one.
run "initial_value_change_ignored" {
  variables {
    initial_secret_string = "{\"api_url\":\"https://changed.example.com\"}"
  }
  assert {
    condition     = nonsensitive(aws_secretsmanager_secret_version.initial[0].secret_string) == "{\"api_url\":\"https://api.example.com\"}"
    error_message = "Later changes to initial_secret_string should be ignored."
  }
}

run "kms_replicas_and_readers" {
  variables {
    kms_key_id = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    replica_regions = [
      { region = "us-west-2" },
    ]
    read_principal_arns = ["arn:aws:iam::222222222222:role/reader"]
  }
  assert {
    condition     = length(aws_secretsmanager_secret.this.replica) == 1
    error_message = "Expected one replica."
  }
  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].block_public_policy == true
    error_message = "Resource policy should block public policies."
  }
  assert {
    condition     = tolist(data.aws_iam_policy_document.resource[0].statement[0].principals)[0].identifiers == toset(["arn:aws:iam::222222222222:role/reader"])
    error_message = "Resource policy should grant the given readers."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.read.statement) == 2
    error_message = "Read policy should include kms:Decrypt on the key ARN."
  }
}

run "kms_alias_no_decrypt_statement" {
  variables {
    kms_key_id = "alias/my-key"
  }
  assert {
    condition     = length(data.aws_iam_policy_document.read.statement) == 1
    error_message = "A non-ARN kms_key_id should not produce a kms:Decrypt statement."
  }
}

run "invalid_recovery_window" {
  command = plan
  variables {
    recovery_window_in_days = 3
  }
  expect_failures = [var.recovery_window_in_days]
}
