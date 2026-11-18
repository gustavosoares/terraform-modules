# S3 Bucket Module

A Terraform module for creating a secure-by-default S3 bucket with optional KMS encryption, lifecycle rules, access logging, CloudFront Origin Access Control, and EKS IRSA access.

## Features

- **SSE-KMS encryption by default** with a dedicated, auto-rotating KMS key (or bring your own key, or use SSE-S3/AES-256)
- Public access blocked by default
- Versioning enabled by default
- Optional TLS-only bucket policy, merged with your own custom policy
- Prefix-scoped lifecycle rules: expiration, storage-class transitions (IA / Glacier / Deep Archive), noncurrent-version cleanup, and aborting incomplete multipart uploads
- Simple auto-delete rules (all objects, or only objects with a tag)
- Optional S3 server access logging
- Optional CloudFront Origin Access Control (OAC) read access, including KMS key grants
- Optional cross-account KMS key access
- Optional IRSA role for EKS pods
- CORS, EventBridge notifications, and object ownership controls

## Bucket Naming

By default the bucket is named `<bucket_name_prefix>-<name>-<environment>`. If `bucket_name_prefix` is not set, the name is `<name>-<environment>`. Set `custom_bucket_name` to use an exact name instead.

S3 bucket names are globally unique, so a prefix (your org, project, or account alias) helps avoid collisions.

## Usage

### Basic Example

```hcl
module "assets_bucket" {
  source = "./modules/s3-bucket"

  bucket_name_prefix = "acme"
  name               = "assets"
  environment        = "prod"

  disable_acls                          = true
  attach_deny_insecure_transport_policy = true

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
# Creates bucket "acme-assets-prod" with a dedicated KMS key
```

### SSE-S3 (AES-256) Instead of KMS

```hcl
module "logs_bucket" {
  source = "./modules/s3-bucket"

  name        = "app-logs"
  environment = "dev"

  kms_encryption_enabled    = false
  aes256_encryption_enabled = true
  versioning_enabled        = false
}
```

### Using an Existing KMS Key

```hcl
module "data_bucket" {
  source = "./modules/s3-bucket"

  name        = "data"
  environment = "prod"

  use_custom_kms_key = true
  kms_key_arn        = aws_kms_key.shared.arn
}
```

### Lifecycle Rules with Storage-Class Transitions

```hcl
module "archive_bucket" {
  source = "./modules/s3-bucket"

  name        = "archive"
  environment = "prod"

  lifecycle_rules = [
    {
      id     = "tier-reports"
      prefix = "reports/"
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER_IR" },
        { days = 365, storage_class = "DEEP_ARCHIVE" },
      ]
      noncurrent_transitions = [
        { days = 30, storage_class = "GLACIER" },
      ]
      noncurrent_expiration_days = 180
    },
    {
      id              = "expire-tmp"
      prefix          = "tmp/"
      expiration_days = 7
    },
    {
      id                           = "cleanup"
      expired_object_delete_marker = true
      abort_incomplete_upload_days = 7
    },
  ]
}
```

`lifecycle_rules` cannot be combined with `auto_delete_files_rule_enabled` / `auto_delete_objects_rule_enabled`. S3 allows only one lifecycle configuration per bucket.

### Auto-Delete Objects After N Days

```hcl
module "scratch_bucket" {
  source = "./modules/s3-bucket"

  name        = "scratch"
  environment = "dev"

  # Expire everything after 14 days
  auto_delete_files_rule_enabled    = true
  auto_delete_files_expiration_days = 14

  # Or: only expire objects tagged auto-delete=true
  # auto_delete_objects_rule_enabled         = true
  # auto_delete_objects_rule_expiration_days = 3
}
```

### With Server Access Logging

```hcl
module "app_bucket" {
  source = "./modules/s3-bucket"

  name        = "app"
  environment = "prod"

  enable_access_logging                  = true
  access_logging_destination_bucket_name = "acme-s3-access-logs-prod"
  # access_logging_target_prefix         = "app/"  # defaults to "<bucket-name>/"
}
```

The destination bucket must exist in the same account and region, and its bucket policy must allow the `logging.s3.amazonaws.com` service principal to `s3:PutObject`. The destination bucket should use SSE-S3, because S3 server access logs cannot be delivered to a bucket whose default encryption is SSE-KMS.

### CloudFront Origin Access Control

```hcl
module "site_bucket" {
  source = "./modules/s3-bucket"

  name        = "website"
  environment = "prod"

  disable_acls                     = true
  cloudfront_oac_distribution_arns = [aws_cloudfront_distribution.site.arn]
}
```

This grants `cloudfront.amazonaws.com` `s3:GetObject` on the bucket, scoped to the listed distributions. It also grants use of the module-created KMS key.

To avoid a dependency cycle when the CloudFront distribution and the bucket are defined in the same module, set `manage_kms_key_policy = false` and manage the bucket and key policies yourself with `aws_s3_bucket_policy` / `aws_kms_key_policy`.

### Cross-Account KMS Access

```hcl
module "shared_bucket" {
  source = "./modules/s3-bucket"

  name        = "shared"
  environment = "prod"

  kms_external_encryption_account_ids = ["111111111111", "222222222222"]
  kms_external_role_name              = "ci-deploy-role" # role that must exist in each external account
  # kms_external_use_root_account     = true             # or delegate to each account's root instead
  # kms_external_allow_decrypt        = false            # write-only (GenerateDataKey)
}
```

You also need a bucket policy (`attach_policy` + `bucket_policy`) that grants the external principals S3 access.

### Custom Bucket Policy

```hcl
data "aws_iam_policy_document" "read_only" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::acme-reports-prod/*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::111111111111:role/reporting"]
    }
  }
}

module "reports_bucket" {
  source = "./modules/s3-bucket"

  bucket_name_prefix = "acme"
  name               = "reports"
  environment        = "prod"

  attach_policy                         = true
  bucket_policy                         = data.aws_iam_policy_document.read_only.json
  attach_deny_insecure_transport_policy = true
}
```

The custom policy, the TLS-only statement, and the CloudFront OAC statement are merged into a single bucket policy.

## IRSA (EKS pod access)

When `create_irsa_role` is `true`, the module creates an IAM role that trusts the cluster's OIDC provider. Pods can then get read/write access to the bucket through **IAM Roles for Service Accounts**.

```hcl
module "uploads_bucket" {
  source = "./modules/s3-bucket"

  name        = "uploads"
  environment = "prod"

  create_irsa_role          = true
  oidc_provider_arn         = aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url         = aws_iam_openid_connect_provider.eks.url
  k8s_namespace             = "my-app"
  irsa_service_account_name = "my-app" # recommended; empty = any SA in the namespace
}
```

Annotate the Kubernetes `ServiceAccount` with:

```yaml
eks.amazonaws.com/role-arn: <irsa_role_arn output>
```

**Important:** A `ServiceAccount` can only carry **one** `eks.amazonaws.com/role-arn`. If the service account already uses IRSA for another role, either:

- Attach this module's `irsa_policy_arn` to the existing role with `aws_iam_role_policy_attachment` and leave `create_irsa_role = false`, or
- Use a dedicated service account for workloads that need this bucket, and set `irsa_service_account_name` to match it.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.22.0 |

## Inputs

### Required

| Name | Description | Type |
|------|-------------|------|
| `name` | Base name of the bucket | `string` |
| `environment` | Environment name (e.g. dev, staging, prod); used in the bucket name and KMS alias | `string` |

### Naming & Tagging

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `bucket_name_prefix` | Optional prefix for the generated bucket name | `string` | `null` |
| `custom_bucket_name` | Exact bucket name, overriding the generated name | `string` | `null` |
| `aws_account_id` | Account that owns the bucket/key; defaults to the current caller's account | `string` | `null` |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` |

### Encryption

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `kms_encryption_enabled` | Enable SSE-KMS encryption | `bool` | `true` |
| `aes256_encryption_enabled` | Enable SSE-S3 (AES-256); used only when KMS is disabled | `bool` | `false` |
| `use_custom_kms_key` | Use `kms_key_arn` instead of creating a key | `bool` | `false` |
| `kms_key_arn` | ARN of an existing KMS key | `string` | `""` |
| `manage_kms_key_policy` | Set the policy on the module-created key | `bool` | `true` |
| `kms_external_encryption_account_ids` | External accounts allowed to use the key | `list(string)` | `[]` |
| `kms_external_role_name` | Role name in each external account (required unless using root) | `string` | `null` |
| `kms_external_use_root_account` | Grant external accounts' root principals instead of a role | `bool` | `false` |
| `kms_external_allow_decrypt` | Also allow `kms:Decrypt` / `kms:DescribeKey` for external accounts | `bool` | `true` |

### Access Control & Policy

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `block_public_acls` | Block public ACLs (forced true when `disable_acls`) | `bool` | `true` |
| `restrict_public_buckets` | Restrict buckets with public policies | `bool` | `true` |
| `disable_acls` | Disable ACLs (`BucketOwnerEnforced`) | `bool` | `false` |
| `control_object_ownership` | Configure object ownership via `object_ownership` | `bool` | `false` |
| `object_ownership` | `BucketOwnerPreferred`, `BucketOwnerEnforced`, or `ObjectWriter` | `string` | `"BucketOwnerPreferred"` |
| `attach_policy` | Attach the custom `bucket_policy` | `bool` | `false` |
| `bucket_policy` | Custom JSON bucket policy | `string` | `null` |
| `attach_deny_insecure_transport_policy` | Deny non-TLS requests | `bool` | `false` |
| `cloudfront_oac_distribution_arns` | CloudFront distributions allowed to read via OAC | `list(string)` | `[]` |

### Features

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `versioning_enabled` | Enable object versioning | `bool` | `true` |
| `eventbridge_notifications` | Send bucket events to EventBridge | `bool` | `false` |
| `cors_configuration_enabled` | Add a CORS configuration | `bool` | `false` |
| `cors_allowed_methods` | Allowed CORS methods | `list(string)` | `[]` |
| `cors_allowed_origins` | Allowed CORS origins | `list(string)` | `[]` |
| `enable_access_logging` | Enable S3 server access logging | `bool` | `false` |
| `access_logging_destination_bucket_name` | Bucket receiving access logs | `string` | `null` |
| `access_logging_target_prefix` | Log object key prefix (defaults to `<bucket-name>/`) | `string` | `null` |

### Lifecycle

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `lifecycle_rules` | Prefix-scoped rules (see below) | `list(object)` | `[]` |
| `auto_delete_files_rule_enabled` | Expire all objects | `bool` | `false` |
| `auto_delete_files_rule_id` | Rule ID | `string` | `"rule-1"` |
| `auto_delete_files_expiration_days` | Days before all objects expire | `number` | `30` |
| `auto_delete_objects_rule_enabled` | Expire objects with a given tag | `bool` | `false` |
| `auto_delete_objects_rule_id` | Rule ID | `string` | `"rule-2"` |
| `auto_delete_objects_rule_expiration_days` | Days before tagged objects expire | `number` | `30` |
| `auto_delete_objects_rule_tag_key` | Tag key marking objects for deletion | `string` | `"auto-delete"` |
| `auto_delete_objects_rule_tag_value` | Tag value marking objects for deletion | `string` | `"true"` |

`lifecycle_rules` object fields:

| Field | Description | Type | Default |
|-------|-------------|------|---------|
| `id` | Unique rule ID | `string` | required |
| `prefix` | Key prefix the rule applies to (`""` = whole bucket) | `string` | `""` |
| `expiration_days` | Days before current objects expire | `number` | `null` |
| `expired_object_delete_marker` | Remove expired delete markers (not combinable with `expiration_days`) | `bool` | `false` |
| `noncurrent_expiration_days` | Days before noncurrent versions expire | `number` | `null` |
| `abort_incomplete_upload_days` | Days before incomplete multipart uploads are aborted | `number` | `null` |
| `transitions` | List of `{ days, storage_class }` for current objects | `list(object)` | `[]` |
| `noncurrent_transitions` | List of `{ days, storage_class }` for noncurrent versions | `list(object)` | `[]` |

Valid `storage_class` values: `STANDARD_IA`, `ONEZONE_IA`, `INTELLIGENT_TIERING`, `GLACIER_IR`, `GLACIER`, `DEEP_ARCHIVE`.

### IRSA

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_irsa_role` | Create an IRSA role for EKS pods | `bool` | `false` |
| `oidc_provider_arn` | EKS OIDC provider ARN (required with IRSA) | `string` | `""` |
| `oidc_provider_url` | EKS OIDC issuer URL (required with IRSA) | `string` | `""` |
| `k8s_namespace` | Namespace allowed to assume the role | `string` | `"default"` |
| `irsa_service_account_name` | Restrict to one service account (recommended) | `string` | `""` |

## Outputs

| Name | Description |
|------|-------------|
| `name` | Name (ID) of the bucket |
| `arn` | ARN of the bucket |
| `regional_domain_name` | Region-specific bucket domain name |
| `kms_key_arn` | ARN of the KMS key encrypting the bucket; null when SSE-KMS is disabled |
| `kms_key_id` | ID of the module-created KMS key; null otherwise |
| `irsa_role_arn` | ARN of the IRSA role; null when not created |
| `irsa_policy_arn` | ARN of the IRSA policy; null when not created |
