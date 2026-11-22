---
name: new-terraform-module
description: Scaffold or review a module in this terraform-modules repo so it follows the repo's conventions. Use when the user asks to create, add, update, or clean up a Terraform module here, or to check a module is generic and publishable.
---

# Terraform module conventions

This is a **public** repo of reusable AWS modules. Every module must be generic, safe by default, and documented. Apply these rules when creating a module and when reviewing or changing an existing one.

## Layout

Each module is a top-level directory (CI discovers modules by the presence of `versions.tf`):

```
<module>/
  main.tf        # resources; locals and data sources may live here too
  variables.tf   # inputs, grouped with `# ===` section banners
  outputs.tf     # every output has a description
  versions.tf    # required_version + required_providers
  README.md
```

Split large features into their own file (e.g. `vpc/flow-logs.tf`, `vpc/vpn_gateway.tf`).

## versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
```

- Declare **minimums only**, never pins or upper bounds; callers pin in their root stacks.
- Raise the AWS provider minimum only when an argument needs it, and leave a comment naming the argument (see `s3-bucket/versions.tf`).
- Never commit `.terraform.lock.hcl` (gitignored) or `.terraform/`.

## Inputs and outputs

- Every variable and output has a `description`. Every variable has a `type`.
- Required inputs should be few. Default everything else to the **safe** choice: encryption on, public access blocked, deletion protection off only when explicit.
- Optional maps and lists default to `{}` or `[]`, never required. `tags` defaults to `{}` and is applied to every taggable resource.
- Use `validation` blocks for enumerations and ranges, and `lifecycle { precondition }` for cross-variable rules.
- Optional features use `count = var.enable_x ? 1 : 0`. Outputs for optional resources return `null` when disabled. Never return placeholder strings like `"NOT_ENCRYPTED"`.
- Don't declare variables that nothing uses. Remove them or implement them.
- Look up account ID and region with `data "aws_caller_identity"` / `data "aws_region"` instead of requiring them (an optional override input is fine).
- Don't put `prevent_destroy` in shared modules; callers can't turn it off.

## No organizational or personal information

Before finishing, sweep the module (code **and** README) and remove or genericize:

- Company, product, team, app, or service names (in resource names, bucket prefixes, tags, descriptions, comments, examples)
- Internal tool conventions (e.g. compliance-tool tags, internal role names like a CI role used as a default)
- Real account IDs, ARNs, resource IDs, domains, emails, Kubernetes namespaces/service accounts
- References to sibling modules or repos that don't exist here
- Non-RFC1918 or company-specific CIDRs. Use `10.0.0.0/16` / `172.20.0.0/16`
- Regions other than the generic examples (`us-east-1`, `us-west-2`)

Use placeholders: `acme`, `my-app`, `example`, `111111111111`, `vgw-12345678`.

Quick sweep from the repo root (review each hit):

```sh
grep -rnE --exclude-dir=.git --exclude-dir=.terraform \
  '\b[0-9]{12}\b|[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}|https?://|\b(vpc|subnet|sg|vgw|igw)-[0-9a-f]{8,17}\b' <module>/
```

Also check `git log -p` if the content was ever committed. A public repo exposes history.

## README

Follow `vpc/README.md` and `s3-bucket/README.md`:

1. `# <Name> Module` and a one-line summary
2. `## Features` (bullets)
3. `## Usage`: a basic example first, then one `###` example per feature. Examples must be copy-pasteable and use generic placeholders.
4. Feature-specific notes or caveats (e.g. IRSA, bucket naming)
5. `## Requirements` table matching `versions.tf`
6. `## Inputs` tables (grouped like `variables.tf`) and `## Outputs` table. Keep them in sync with the code.

Then add the module to the **Modules** table in the root `README.md`.

## Verify before finishing

From the module directory:

```sh
terraform fmt -recursive
terraform init -backend=false -input=false
terraform validate
rm -rf .terraform .terraform.lock.hcl   # don't leave init artifacts
```

Terraform may not be on PATH in the agent shell; try `/opt/homebrew/bin/terraform`. If it isn't installed, say so rather than claiming the module validates.

CI (`.github/workflows/terraform.yml`) runs fmt and validate only on modules changed in a PR, and the required `terraform-checks` status must pass before merging to `main`.

## Don't

- Don't commit or push unless asked. `main` is protected and only accepts PRs.
- Don't claim something is "tested" when only `validate` has run. `validate` checks syntax and types, not real deploys.
