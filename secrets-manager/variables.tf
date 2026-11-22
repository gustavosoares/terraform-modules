variable "name" {
  description = "Secret name, e.g. \"my-app/config\""
  type        = string
}

variable "description" {
  description = "Secret description"
  type        = string
  default     = null
}

variable "kms_key_id" {
  description = "KMS key ARN to encrypt the secret. null uses the AWS managed key (aws/secretsmanager). Use an ARN so read_policy_json can grant kms:Decrypt"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Days AWS keeps a deleted secret before removing it: 0 (delete immediately) or 7-30"
  type        = number
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "replica_regions" {
  description = "Regions to replicate the secret to, each with an optional KMS key in that region"
  type = list(object({
    region     = string
    kms_key_id = optional(string)
  }))
  default = []
}

variable "initial_secret_string" {
  description = "Initial secret value (e.g. jsonencode({...})). Later changes are ignored so values set outside Terraform aren't overwritten. The value is stored in Terraform state. null creates the secret without a value"
  type        = string
  default     = null
  sensitive   = true
}

variable "read_principal_arns" {
  description = "IAM principal ARNs (roles, users or account roots) allowed to read the secret through the resource policy. Same-account principals can instead use read_policy_json in their own IAM policy"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default     = {}
}
