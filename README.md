# terraform-modules

A collection of small, reusable Terraform modules for AWS. Each module is secure by default, has few required inputs, and is documented with copy-pasteable examples.

## Modules

| Module | Description |
|--------|-------------|
| [vpc](./vpc) | VPC with public/private subnets per AZ, single or per-AZ NAT gateways, optional VPN gateway, and optional VPC Flow Logs to S3 |
| [autoscaling](./autoscaling) | EC2 Auto Scaling Group with launch template, security group, IAM instance profile, scaling policies, Spot/mixed instances, warm pools, and instance refresh |
| [ec2-instance](./ec2-instance) | Single EC2 instance with security group, IAM role/instance profile, IMDSv2 and encrypted root volume by default, and an optional stop/start schedule |
| [s3-bucket](./s3-bucket) | S3 bucket with SSE-KMS by default, public access blocked, lifecycle rules and storage-class transitions, access logging, CloudFront OAC, cross-account KMS, and EKS IRSA access |
| [lambda-function](./lambda-function) | Lambda function with a least-privilege role and managed log group, zip/S3/container code (or CI-deployed), optional VPC access, SQS and schedule triggers, async dead-letter queue, and an errors alarm |
| [ecr](./ecr) | ECR repository with immutable tags, scan on push, lifecycle cleanup, and optional cross-account and Lambda pull access |
| [secrets-manager](./secrets-manager) | Secrets Manager secret with optional KMS, replication, initial value, cross-account resource policy, and a ready-made read policy output |

See each module's README for its inputs, outputs, and usage examples.

## Usage

Reference a module directly from this repository with a Git source. Pin `ref` to a release tag so upgrades are deliberate:

```hcl
module "vpc" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//vpc?ref=v0.1.0"

  vpc_cidr_block = "10.0.0.0/16"

  public_subnets = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }

  private_subnets = {
    "us-east-1a" = "10.0.101.0/24"
    "us-east-1b" = "10.0.102.0/24"
  }
}

module "assets_bucket" {
  source = "git::https://github.com/gustavosoares/terraform-modules.git//s3-bucket?ref=v0.1.0"

  name        = "assets"
  environment = "prod"
}
```

The double slash (`//`) separates the repository URL from the module's subdirectory.

## Requirements

| Name | Version |
|------|---------|
| Terraform (or OpenTofu) | >= 1.5.0 |
| AWS provider | >= 6.0 (s3-bucket requires >= 6.22.0) |

Modules declare minimum versions only. Pin exact provider versions in your root configuration and commit its `.terraform.lock.hcl`.

## Versioning

Releases follow [Semantic Versioning](https://semver.org/) and are tagged repository-wide (e.g. `v1.2.0`):

- **MAJOR**: breaking changes, such as renamed or removed inputs or changes that force resource replacement
- **MINOR**: new, backwards-compatible features and inputs
- **PATCH**: backwards-compatible bug fixes and documentation

Read the release notes before upgrading across a major version.

## Development

### Installing Terraform with tfenv

[tfenv](https://github.com/tfutils/tfenv) installs multiple Terraform versions side by side and switches between them.

```sh
# macOS (Homebrew)
brew install tfenv

# Linux (or macOS without Homebrew)
git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
```

Then install and select a version:

```sh
tfenv install latest      # or a specific version, e.g. tfenv install 1.17.2
tfenv use latest
terraform version
```

This repository includes a [`.terraform-version`](./.terraform-version) file that pins the Terraform version used for development and CI checks. From the repo root, run:

```sh
tfenv install   # installs the version in .terraform-version
```

tfenv picks it up automatically in any subdirectory. The pin only affects local tooling. The modules themselves accept any Terraform version allowed by their `required_version` (>= 1.5.0).

> If you already have Terraform installed through Homebrew, run `brew unlink terraform` first so it doesn't shadow the tfenv-managed binary.

### Checks

Before opening a pull request, run these in the changed module's directory:

```sh
terraform fmt -recursive
terraform init -backend=false
terraform validate
terraform test
```

`terraform test` runs the module's `tests/*.tftest.hcl` against a mocked AWS provider, so it needs no AWS credentials and creates nothing. The tests use `mock_provider` and `state_key`, so they need Terraform 1.9 or later (the pinned development version is newer); the modules themselves still support >= 1.5.0.

CI runs these checks, plus `init` and `validate` in each `examples/*` folder, for every module a pull request changes. It also checks modules that use a changed module as a local source, such as an example with `source = "../../../ecr"`. Changes to `.terraform-version` or the workflow check every module.

When adding a module:

- Put it in its own top-level directory with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a `README.md`
- Give every variable and output a `description`, and use defaults that are safe without changes
- Don't hardcode account IDs, regions, or names; take them as inputs or look them up with data sources
- Add mocked tests in `tests/` covering the defaults, each optional feature, and every validation and precondition
- Add the module to the table above

---

<sub>Developed with the help of AI coding tools; reviewed and maintained by the author.</sub>
