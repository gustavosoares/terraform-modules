# Lambda Function Module

A Terraform module for an AWS Lambda function with its own IAM role and CloudWatch log group, optional VPC access, SQS and schedule triggers, an async dead-letter queue, and an errors alarm.

## Features

- Zip packages from a local file or S3, or **container images** from ECR
- A placeholder stub is deployed when no code is given, so the function can be created before CI ships real code
- `ignore_code_changes` for code deployed outside Terraform (e.g. by CI)
- **Least-privilege IAM role**: logs permissions are scoped to the function's own log group; add more with managed policy ARNs or inline policy documents
- **Log group managed by the module**, with bounded retention (365 days by default), optional KMS encryption, and an optional subscription filter
- Optional VPC access with a dedicated security group: outbound HTTPS by default, plus your own egress rules
- Optional SQS trigger, with partial batch failure reporting
- Optional EventBridge schedule (`rate(...)` or `cron(...)`)
- Optional async invocation settings with an encrypted SQS dead-letter queue
- Optional CloudWatch alarm on the `Errors` metric, notifying SNS or any alarm action
- Only `name` is required; tags are applied to all resources

## Usage

### Basic Example

```hcl
data "archive_file" "code" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/.terraform/build/hello.zip"
}

module "hello" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name             = "hello"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  runtime          = "python3.13"
  architectures    = ["arm64"]

  environment_variables = {
    LOG_LEVEL = "info"
  }

  tags = {
    Environment = "prod"
  }
}
```

### Code Deployed by CI

Terraform creates the function with the built-in stub and never touches the code again. CI deploys with `aws lambda update-function-code`.

```hcl
module "api" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name                = "api"
  runtime             = "nodejs22.x"
  handler             = "dist/index.handler"
  ignore_code_changes = true
}
```

### Package in S3

```hcl
module "worker" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name = "worker"

  s3_source = {
    bucket = "my-artifacts-bucket"
    key    = "worker/v1.2.0.zip"
  }
  # Changing this hash (or the key) deploys new code
  source_code_hash = var.worker_package_sha256
}
```

### Inside a VPC

The function gets a security group that allows outbound HTTPS to anywhere. Add your own rules for databases and other services. Private subnets need a NAT gateway or VPC endpoints to reach AWS APIs.

```hcl
module "worker" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name = "worker"

  network_config = {
    vpc_id     = module.vpc.vpc_id
    subnet_ids = module.vpc.private_subnet_ids

    egress_rules = {
      postgres = {
        description = "PostgreSQL within the VPC"
        from_port   = 5432
        to_port     = 5432
        cidr_blocks = ["10.0.0.0/16"]
      }
    }
  }
}
```

Set `enable_default_egress = false` to remove the HTTPS rule. Use `additional_security_group_ids` to attach security groups you manage elsewhere.

### SQS Trigger

```hcl
module "consumer" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name = "consumer"

  sqs_trigger = {
    queue_arn                  = aws_sqs_queue.jobs.arn
    batch_size                 = 10
    report_batch_item_failures = true
    # Only needed when the queue uses a customer managed KMS key
    kms_key_arn = aws_kms_key.queue.arn
  }
}
```

The queue's visibility timeout must be at least the function's `timeout`.

### Schedule

```hcl
module "nightly" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name    = "nightly-cleanup"
  timeout = 900

  schedule = {
    expression  = "cron(0 3 * * ? *)" # 03:00 UTC daily
    description = "Nightly cleanup"
    input       = jsonencode({ dry_run = false })
  }
}
```

### Async Retries and Dead-Letter Queue

```hcl
module "events" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name = "events"

  async_config = {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 3600
    create_dead_letter_queue     = true
  }
}
```

Failed async invocations go to an SSE-encrypted queue named `<name>-async-dlq` (see the `dead_letter_queue_*` outputs).

### Errors Alarm

```hcl
module "billing" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name = "billing"

  errors_alarm = {
    threshold     = 1
    period        = 300
    alarm_actions = [aws_sns_topic.alerts.arn]
    ok_actions    = [aws_sns_topic.alerts.arn]
  }
}
```

### Container Image with a Secret

This uses this repo's [ecr](../ecr) and [secrets-manager](../secrets-manager) modules.

```hcl
module "repo" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//ecr?ref=v0.1.0"

  name               = "report"
  enable_lambda_pull = true
}

module "config" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//secrets-manager?ref=v0.1.0"

  name = "report/config"
}

module "report" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//lambda-function?ref=v0.1.0"

  name                = "report"
  image_uri           = "${module.repo.repository_url}:v1.0.0"
  ignore_code_changes = true

  environment_variables = {
    CONFIG_SECRET_ARN = module.config.arn
  }

  iam_policy_documents = [module.config.read_policy_json]
}
```

More complete configurations are in [examples/](./examples).

## Tests

[tests/](./tests) holds `terraform test` runs against a mocked AWS provider, so they need no credentials and create nothing. They check the defaults, every feature enabled together, and input validation:

```sh
terraform init -backend=false
terraform test
```

## Notes

- **Code source**: set at most one of `filename`, `s3_source` or `image_uri`. With none, a stub zip with `index.js` and `index.py` is deployed, so the default `handler = "index.handler"` works for Node.js and Python runtimes. The stub is built at plan time under `<root>/.terraform/`, so apply from the same working directory as plan.
- **`ignore_code_changes`**: Terraform cannot toggle `ignore_changes` dynamically, so the module has two function resources and creates one of them. Changing this flag on an existing function moves it between resources; run `terraform state mv 'module.<name>.aws_lambda_function.this[0]' 'module.<name>.aws_lambda_function.ignore_code[0]'` (or the reverse) first, or Terraform will try to replace the function. Runtime, handler and other settings are still managed either way.
- **Log group**: the module creates `/aws/lambda/<name>` and points the function at it. If a log group with that name already exists (for example from an earlier deploy), import it first.
- **IAM names** use generated prefixes because IAM is global per account, so the same `name` can be deployed in several regions.
- **Out of scope**: aliases and provisioned concurrency, function URLs, API Gateway integrations, and event sources other than SQS and schedules. Add those next to the module using its outputs (`function_name`, `function_arn`, `invoke_arn`, `role_name`).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5.0 |
| aws | >= 6.0 |
| archive | >= 2.0 |

## Inputs

### Required

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Function name, also used as the name or prefix of related resources | `string` | n/a | yes |

### Code

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `filename` | Path to a local deployment package (.zip) | `string` | `null` | no |
| `s3_source` | Package in S3: `{ bucket, key, object_version }` | `object` | `null` | no |
| `image_uri` | ECR image URI for a container image function; `handler` and `runtime` are ignored | `string` | `null` | no |
| `source_code_hash` | Base64 SHA256 of the package; computed for `filename` and the stub, set it for `s3_source` | `string` | `null` | no |
| `handler` | Function entrypoint | `string` | `"index.handler"` | no |
| `runtime` | Lambda runtime | `string` | `"nodejs22.x"` | no |
| `ignore_code_changes` | Ignore code changes after creation (code deployed outside Terraform) | `bool` | `false` | no |

### Function Settings

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `description` | Function description | `string` | `null` | no |
| `memory_size` | Memory in MB (128-10240) | `number` | `256` | no |
| `timeout` | Timeout in seconds (1-900) | `number` | `30` | no |
| `architectures` | `["x86_64"]` or `["arm64"]` | `list(string)` | `["x86_64"]` | no |
| `reserved_concurrent_executions` | Reserved concurrency; -1 = unreserved, 0 = disabled | `number` | `-1` | no |
| `environment_variables` | Environment variables | `map(string)` | `{}` | no |
| `layers` | Layer version ARNs (up to 5) | `list(string)` | `[]` | no |

### IAM

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `iam_policy_arns` | Managed policy ARNs to attach to the role | `list(string)` | `[]` | no |
| `iam_policy_documents` | JSON policy documents added as inline role policies | `list(string)` | `[]` | no |

### Network

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `network_config` | `{ subnet_ids, vpc_id, enable_default_egress = true, egress_rules = {}, additional_security_group_ids = [] }`; null = no VPC. Each egress rule: `{ description, from_port, to_port, protocol = "tcp", cidr_blocks }` | `object` | `null` | no |

### Logs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `log_retention_in_days` | Log retention in days; 0 = forever | `number` | `365` | no |
| `log_kms_key_id` | KMS key ARN for the log group | `string` | `null` | no |
| `log_subscription` | `{ destination_arn, role_arn, filter_pattern = "" }` subscription filter | `object` | `null` | no |

### Triggers, Async Invocation and Alarms

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `sqs_trigger` | `{ queue_arn, batch_size = 10, maximum_batching_window_in_seconds, enabled = true, report_batch_item_failures = false, kms_key_arn }` | `object` | `null` | no |
| `schedule` | `{ expression, description, enabled = true, input }` EventBridge schedule | `object` | `null` | no |
| `async_config` | `{ maximum_retry_attempts, maximum_event_age_in_seconds, create_dead_letter_queue = false, dead_letter_queue_retention_seconds = 1209600 }` | `object` | `null` | no |
| `errors_alarm` | `{ threshold = 1, period = 300, evaluation_periods = 1, treat_missing_data = "notBreaching", alarm_actions = [], ok_actions = [] }` | `object` | `null` | no |
| `tags` | Tags for all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `function_name` | Lambda function name |
| `function_arn` | Lambda function ARN |
| `qualified_arn` | Function ARN including the latest version |
| `invoke_arn` | ARN for invoking the function from API Gateway |
| `version` | Latest published version |
| `role_arn` | Execution role ARN |
| `role_name` | Execution role name |
| `log_group_name` | CloudWatch log group name |
| `log_group_arn` | CloudWatch log group ARN |
| `security_group_id` | Security group ID, or null when not in a VPC |
| `dead_letter_queue_arn` | Async dead-letter queue ARN, or null |
| `dead_letter_queue_url` | Async dead-letter queue URL, or null |
| `errors_alarm_arn` | Errors alarm ARN, or null |
