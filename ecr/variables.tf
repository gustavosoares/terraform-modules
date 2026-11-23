variable "name" {
  description = "Repository name, e.g. \"my-app\" or \"team/my-app\""
  type        = string
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. Immutable tags stop an existing tag from being overwritten"
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Scan images for vulnerabilities when they are pushed"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption. null uses AES256 (S3-managed) encryption"
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Allow deleting the repository while it still contains images"
  type        = bool
  default     = false
}

variable "max_image_count" {
  description = "Lifecycle rule: keep only this many most recent images. null disables the rule"
  type        = number
  default     = 30

  validation {
    condition     = var.max_image_count == null || try(var.max_image_count >= 1, false)
    error_message = "max_image_count must be at least 1, or null."
  }
}

variable "untagged_image_expiration_days" {
  description = "Lifecycle rule: expire untagged images after this many days. null disables the rule"
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_image_expiration_days == null || try(var.untagged_image_expiration_days >= 1, false)
    error_message = "untagged_image_expiration_days must be at least 1, or null."
  }
}

variable "pull_account_ids" {
  description = "Other AWS account IDs allowed to pull images"
  type        = list(string)
  default     = []
}

variable "enable_lambda_pull" {
  description = "Allow Lambda functions in this account and in pull_account_ids to use images from this repository"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default     = {}
}
