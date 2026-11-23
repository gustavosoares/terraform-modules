# ECR Repository Module

A Terraform module for an Amazon ECR repository with immutable tags, scan-on-push, lifecycle cleanup, and optional cross-account and Lambda pull access.

## Features

- **Immutable tags** and **scan on push** by default
- AES256 encryption, or KMS with your own key
- Lifecycle rules: expire untagged images after 7 days and keep the 30 most recent images (both configurable or disableable)
- Optional pull access for other AWS accounts
- Optional pull access for Lambda functions (container image functions), in this account and in the pull accounts
- Repository deletion is blocked while it holds images, unless you set `force_delete`

## Usage

### Basic Example

```hcl
module "repo" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ecr?ref=v0.1.0"

  name = "my-app"

  tags = {
    Environment = "prod"
  }
}
```

### For Lambda Container Images

```hcl
module "repo" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ecr?ref=v0.1.0"

  name               = "my-function"
  enable_lambda_pull = true
}

module "function" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name                = "my-function"
  image_uri           = "${module.repo.repository_url}:v1.0.0"
  ignore_code_changes = true
}
```

### Cross-Account Pull

```hcl
module "repo" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ecr?ref=v0.1.0"

  name             = "shared/base-image"
  pull_account_ids = ["111111111111", "222222222222"]
}
```

Principals in those accounts still need `ecr:GetAuthorizationToken` and the pull actions in their own IAM policies.

### Mutable Tags and KMS

```hcl
module "repo" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ecr?ref=v0.1.0"

  name                 = "dev/my-app"
  image_tag_mutability = "MUTABLE" # e.g. to push a moving "latest" tag
  kms_key_arn          = aws_kms_key.ecr.arn
  max_image_count      = 10
}
```

## Notes

- **Encryption** can't be changed after the repository is created; changing `kms_key_arn` replaces the repository.
- **Lifecycle**: the "keep N images" rule counts every image, tagged or not, and runs after the untagged rule. Set `max_image_count = null` or `untagged_image_expiration_days = null` to drop a rule.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Repository name | `string` | n/a | yes |
| `image_tag_mutability` | `MUTABLE` or `IMMUTABLE` | `string` | `"IMMUTABLE"` | no |
| `scan_on_push` | Scan images on push | `bool` | `true` | no |
| `kms_key_arn` | KMS key ARN; null uses AES256 | `string` | `null` | no |
| `force_delete` | Allow deleting the repository while it holds images | `bool` | `false` | no |
| `max_image_count` | Keep only this many most recent images; null disables | `number` | `30` | no |
| `untagged_image_expiration_days` | Expire untagged images after N days; null disables | `number` | `7` | no |
| `pull_account_ids` | Other AWS account IDs allowed to pull | `list(string)` | `[]` | no |
| `enable_lambda_pull` | Allow Lambda functions in this account and `pull_account_ids` to pull | `bool` | `false` | no |
| `tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `repository_arn` | Repository ARN |
| `repository_name` | Repository name |
| `repository_url` | Repository URL |
| `registry_id` | Registry (account) ID |
