# Secrets Manager Secret Module

A Terraform module for an AWS Secrets Manager secret with optional KMS encryption, replication, an initial value, and a ready-made read policy for the workloads that use it.

## Features

- Encrypted with the AWS managed key by default, or your own KMS key
- 30-day recovery window by default, so a deleted secret can be restored
- Optional replication to other regions
- Optional initial value; later changes made outside Terraform (rotation, console, CLI) are kept
- `read_policy_json` output: an IAM policy that grants read access to this secret only, ready for a Lambda, ECS task or EC2 role
- Optional resource policy for cross-account readers, with public policies blocked

## Usage

### Basic Example

```hcl
module "db_credentials" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//secrets-manager?ref=v0.1.0"

  name        = "my-app/db"
  description = "Database credentials for my-app"

  tags = {
    Environment = "prod"
  }
}
```

Set the value outside Terraform so it never reaches state:

```sh
aws secretsmanager put-secret-value --secret-id my-app/db --secret-string file://db.json
```

### With an Initial Value

```hcl
module "config" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//secrets-manager?ref=v0.1.0"

  name = "my-app/config"

  initial_secret_string = jsonencode({
    api_url = "https://api.example.com"
    api_key = var.api_key
  })
}
```

### Granting a Lambda Function Read Access

```hcl
module "function" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name = "my-app"

  environment_variables = {
    CONFIG_SECRET_ARN = module.config.arn
  }

  iam_policy_documents = [module.config.read_policy_json]
}
```

### KMS, Replication and Cross-Account Read

```hcl
module "shared" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//secrets-manager?ref=v0.1.0"

  name       = "shared/partner-api"
  kms_key_id = aws_kms_key.secrets.arn

  replica_regions = [
    { region = "us-west-2", kms_key_id = "arn:aws:kms:us-west-2:111111111111:key/11111111-2222-3333-4444-555555555555" },
  ]

  read_principal_arns = ["arn:aws:iam::222222222222:role/partner-reader"]
}
```

Cross-account readers also need `kms:Decrypt` on the key, so a customer managed key (not the AWS managed one) is required for them.

## Notes

- **State**: `initial_secret_string` is stored in Terraform state, like any secret value managed by Terraform. Protect the state, or leave it null and set the value with the CLI.
- **Initial value only**: changes to `initial_secret_string` after creation are ignored so that rotation and manual updates aren't overwritten. To change the value from Terraform, taint or replace `aws_secretsmanager_secret_version.initial`.
- **Deletion**: with the default recovery window, a destroyed secret's name stays reserved for 30 days. Use `recovery_window_in_days = 0` for throwaway environments.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Secret name | `string` | n/a | yes |
| `description` | Secret description | `string` | `null` | no |
| `kms_key_id` | KMS key ARN; null uses `aws/secretsmanager` | `string` | `null` | no |
| `recovery_window_in_days` | 0 or 7-30 | `number` | `30` | no |
| `replica_regions` | `[{ region, kms_key_id }]` replicas | `list(object)` | `[]` | no |
| `initial_secret_string` | Initial value (sensitive, stored in state); later changes ignored | `string` | `null` | no |
| `read_principal_arns` | Principals allowed to read via the resource policy | `list(string)` | `[]` | no |
| `tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `arn` | Secret ARN |
| `id` | Secret ID (same as the ARN) |
| `name` | Secret name |
| `read_policy_json` | IAM policy granting read access to this secret (and `kms:Decrypt` when `kms_key_id` is an ARN) |
