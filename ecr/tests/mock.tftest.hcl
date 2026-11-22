# Plan/apply against a mocked AWS provider: no credentials or real resources.
# Run from the module directory: terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name = "my-app"
}

run "defaults" {
  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.this.force_delete == false
    error_message = "Tags should be immutable and deletion protected by default."
  }
  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "Images should be scanned on push."
  }
  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "AES256 should be used without a KMS key."
  }
  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "No repository policy should be created by default."
  }
}

run "lifecycle_policy_rules" {
  assert {
    condition = jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules == [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the 30 most recent images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
        action       = { type = "expire" }
      },
    ]
    error_message = "Default lifecycle policy should expire untagged images, then keep 30 images, with the 'any' rule last."
  }
}

run "single_lifecycle_rule" {
  variables {
    untagged_image_expiration_days = null
    max_image_count                = 5
  }
  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules) == 1 && jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.countNumber == 5
    error_message = "Only the keep-N rule should remain, with priority 1."
  }
}

run "no_lifecycle" {
  variables {
    untagged_image_expiration_days = null
    max_image_count                = null
  }
  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "No lifecycle policy when both rules are disabled."
  }
}

run "kms_mutable" {
  variables {
    kms_key_arn          = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    image_tag_mutability = "MUTABLE"
  }
  assert {
    condition = (
      aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS" &&
      aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    )
    error_message = "KMS encryption should use the given key."
  }
}

run "cross_account_and_lambda_pull" {
  variables {
    pull_account_ids   = ["222222222222"]
    enable_lambda_pull = true
  }
  assert {
    condition     = length(aws_ecr_repository_policy.this) == 1 && length(data.aws_iam_policy_document.this[0].statement) == 2
    error_message = "Expected cross-account and Lambda statements."
  }
  assert {
    condition = (
      tolist(one([for s in data.aws_iam_policy_document.this[0].statement : s if s.sid == "CrossAccountPull"]).principals)[0].identifiers ==
      toset(["arn:aws:iam::222222222222:root"])
    )
    error_message = "Cross-account pull should grant the other account's root."
  }
  assert {
    condition = (
      toset(one(one([for s in data.aws_iam_policy_document.this[0].statement : s if s.sid == "LambdaPull"]).condition).values) ==
      toset(["arn:aws:lambda:*:111111111111:function:*", "arn:aws:lambda:*:222222222222:function:*"])
    )
    error_message = "Lambda pull should be limited to functions in this account and the pull accounts."
  }
}

run "invalid_mutability" {
  command = plan
  variables {
    image_tag_mutability = "SOMETIMES"
  }
  expect_failures = [var.image_tag_mutability]
}

run "invalid_image_count" {
  command = plan
  variables {
    max_image_count = 0
  }
  expect_failures = [var.max_image_count]
}
