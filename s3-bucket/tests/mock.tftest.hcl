# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "assets-prod"
      arn = "arn:aws:s3:::assets-prod"
    }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/assets-prod-s3-access-policy" }
  }
}

variables {
  name        = "assets"
  environment = "prod"
}

run "defaults" {
  assert {
    condition     = aws_s3_bucket.s3_bucket.bucket == "assets-prod"
    error_message = "Bucket should be named <name>-<environment>."
  }
  assert {
    condition     = length(aws_kms_key.s3_bucket_key) == 1 && aws_kms_key.s3_bucket_key[0].enable_key_rotation == true
    error_message = "A rotating KMS key should be created by default."
  }
  assert {
    condition     = aws_kms_alias.s3_bucket_key_alias[0].name == "alias/assets-prod-bucket-key"
    error_message = "KMS alias should be alias/<name>-<environment>-bucket-key."
  }
  assert {
    condition = (
      one(aws_s3_bucket_server_side_encryption_configuration.encryption_config[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms" &&
      one(aws_s3_bucket_server_side_encryption_configuration.encryption_config[0].rule).apply_server_side_encryption_by_default[0].kms_master_key_id == aws_kms_key.s3_bucket_key[0].arn
    )
    error_message = "Bucket should use SSE-KMS with the module key."
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.s3_bucket_public_access_block.block_public_acls &&
      aws_s3_bucket_public_access_block.s3_bucket_public_access_block.block_public_policy &&
      aws_s3_bucket_public_access_block.s3_bucket_public_access_block.ignore_public_acls &&
      aws_s3_bucket_public_access_block.s3_bucket_public_access_block.restrict_public_buckets
    )
    error_message = "All public access should be blocked by default."
  }
  assert {
    condition     = aws_s3_bucket_versioning.versioning.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning should be enabled by default."
  }
  assert {
    condition = (
      length(aws_s3_bucket_policy.bucket_policy) == 0 &&
      length(aws_s3_bucket_lifecycle_configuration.prefix_scoped) == 0 &&
      length(aws_s3_bucket_lifecycle_configuration.auto_delete_files_policy) == 0 &&
      length(aws_s3_bucket_ownership_controls.ownership) == 0 &&
      length(aws_iam_role.irsa_s3_access) == 0
    )
    error_message = "Optional features should be off by default."
  }
  assert {
    condition     = output.kms_key_arn == aws_kms_key.s3_bucket_key[0].arn && output.irsa_role_arn == null
    error_message = "Outputs should reflect the module key and no IRSA role."
  }
}

run "name_prefix" {
  variables {
    bucket_name_prefix = "acme"
  }
  assert {
    condition     = aws_s3_bucket.s3_bucket.bucket == "acme-assets-prod"
    error_message = "Prefix should be prepended to the generated name."
  }
}

run "custom_name" {
  variables {
    bucket_name_prefix = "acme"
    custom_bucket_name = "my-exact-bucket"
  }
  assert {
    condition     = aws_s3_bucket.s3_bucket.bucket == "my-exact-bucket"
    error_message = "custom_bucket_name should override the generated name."
  }
}

run "aes256" {
  variables {
    kms_encryption_enabled    = false
    aes256_encryption_enabled = true
  }
  assert {
    condition     = length(aws_kms_key.s3_bucket_key) == 0 && output.kms_key_arn == null
    error_message = "No KMS key should be created for SSE-S3."
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.encryption_config[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Bucket should use AES256."
  }
}

run "custom_kms_key" {
  variables {
    use_custom_kms_key = true
    kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/99999999-8888-7777-6666-555555555555"
  }
  assert {
    condition     = length(aws_kms_key.s3_bucket_key) == 0 && length(aws_kms_alias.s3_bucket_key_alias) == 0
    error_message = "No key or alias should be created with a custom key."
  }
  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:us-east-1:111111111111:key/99999999-8888-7777-6666-555555555555" && output.kms_key_id == null
    error_message = "Outputs should point at the custom key."
  }
}

run "disable_acls_forces_public_acl_block" {
  variables {
    disable_acls      = true
    block_public_acls = false
  }
  assert {
    condition     = aws_s3_bucket_ownership_controls.ownership[0].rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "disable_acls should enforce bucket-owner ownership."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.s3_bucket_public_access_block.block_public_acls == true
    error_message = "disable_acls should force block_public_acls."
  }
}

run "combined_bucket_policy" {
  variables {
    attach_deny_insecure_transport_policy = true
    cloudfront_oac_distribution_arns      = ["arn:aws:cloudfront::111111111111:distribution/EDFDVBD6EXAMPLE"]
  }
  assert {
    condition     = length(aws_s3_bucket_policy.bucket_policy) == 1 && length(data.aws_iam_policy_document.combined_policy[0].source_policy_documents) == 2
    error_message = "TLS-only and CloudFront statements should be merged into one bucket policy."
  }
  assert {
    condition = (
      one(data.aws_iam_policy_document.deny_insecure_transport[0].statement[0].condition).variable == "aws:SecureTransport" &&
      tolist(one(data.aws_iam_policy_document.deny_insecure_transport[0].statement[0].condition).values) == tolist(["false"])
    )
    error_message = "Insecure transport statement should match aws:SecureTransport = false."
  }
  assert {
    condition     = length([for s in data.aws_iam_policy_document.kms_bucket_policy.statement : s if s.sid == "AllowCloudFrontServicePrincipalSSE-KMS"]) == 1
    error_message = "KMS key policy should let CloudFront use the key."
  }
}

run "external_kms_root_accounts" {
  variables {
    kms_external_encryption_account_ids = ["222222222222"]
    kms_external_use_root_account       = true
    kms_external_allow_decrypt          = false
  }
  assert {
    condition     = contains(flatten([for s in data.aws_iam_policy_document.kms_bucket_policy.statement : [for p in s.principals : p.identifiers]]), "arn:aws:iam::222222222222:root")
    error_message = "External account root should be a KMS principal."
  }
  assert {
    condition     = contains([for s in data.aws_iam_policy_document.kms_bucket_policy.statement : s.actions], toset(["kms:GenerateDataKey"]))
    error_message = "Without decrypt, external accounts should only get kms:GenerateDataKey."
  }
}

run "lifecycle_rules" {
  variables {
    lifecycle_rules = [
      {
        id                           = "logs"
        prefix                       = "logs/"
        expiration_days              = 365
        abort_incomplete_upload_days = 7
        transitions                  = [{ days = 30, storage_class = "STANDARD_IA" }, { days = 90, storage_class = "GLACIER" }]
      },
      {
        id                         = "old-versions"
        noncurrent_expiration_days = 30
      },
    ]
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.prefix_scoped[0].rule) == 2
    error_message = "Expected two lifecycle rules."
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.prefix_scoped[0].rule[0].transition) == 2 && aws_s3_bucket_lifecycle_configuration.prefix_scoped[0].rule[0].filter[0].prefix == "logs/"
    error_message = "Transitions and prefix should be passed through."
  }
}

run "auto_delete_rules" {
  variables {
    auto_delete_files_rule_enabled    = true
    auto_delete_files_expiration_days = 7
    auto_delete_objects_rule_enabled  = true
  }
  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.auto_delete_files_policy[0].rule) == 2
    error_message = "Both auto-delete rules should be in one lifecycle configuration."
  }
  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.auto_delete_files_policy[0].rule[1].filter[0].tag[0].key == "auto-delete"
    error_message = "Tag rule should use the default auto-delete tag."
  }
}

run "access_logging_default_prefix" {
  variables {
    enable_access_logging                  = true
    access_logging_destination_bucket_name = "my-log-bucket"
  }
  assert {
    condition     = aws_s3_bucket_logging.access_logging[0].target_prefix == "assets-prod/"
    error_message = "Access log prefix should default to <bucket>/."
  }
}

run "irsa_single_service_account" {
  variables {
    create_irsa_role          = true
    oidc_provider_arn         = "arn:aws:iam::111111111111:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    oidc_provider_url         = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
    k8s_namespace             = "apps"
    irsa_service_account_name = "uploader"
  }
  assert {
    condition = (
      jsondecode(aws_iam_role.irsa_s3_access[0].assume_role_policy).Statement[0].Condition.StringLike["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"] ==
      "system:serviceaccount:apps:uploader"
    )
    error_message = "IRSA trust should be limited to the given service account."
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.irsa_s3_access) == 1
    error_message = "IRSA policy should be attached."
  }
}

run "external_kms_needs_role_name" {
  command = plan
  variables {
    kms_external_encryption_account_ids = ["222222222222"]
  }
  expect_failures = [data.aws_iam_policy_document.kms_bucket_policy]
}

run "lifecycle_with_auto_delete" {
  command = plan
  variables {
    lifecycle_rules                = [{ id = "logs", expiration_days = 30 }]
    auto_delete_files_rule_enabled = true
  }
  expect_failures = [aws_s3_bucket_lifecycle_configuration.prefix_scoped]
}

run "lifecycle_rule_without_action" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "empty" }]
  }
  expect_failures = [aws_s3_bucket_lifecycle_configuration.prefix_scoped]
}

run "invalid_storage_class" {
  command = plan
  variables {
    lifecycle_rules = [{ id = "bad", transitions = [{ days = 30, storage_class = "COLD" }] }]
  }
  expect_failures = [var.lifecycle_rules]
}

run "access_logging_needs_bucket" {
  command = plan
  variables {
    enable_access_logging = true
  }
  expect_failures = [aws_s3_bucket_logging.access_logging]
}

run "irsa_needs_oidc" {
  command = plan
  variables {
    create_irsa_role = true
  }
  expect_failures = [aws_iam_role.irsa_s3_access]
}
