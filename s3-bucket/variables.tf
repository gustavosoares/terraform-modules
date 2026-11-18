# =============================================================================
# Required Variables
# =============================================================================

variable "name" {
  type        = string
  description = "Base name of the bucket. The final name is '<bucket_name_prefix>-<name>-<environment>' unless custom_bucket_name is set."
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, staging, prod). Used in the bucket name and KMS key alias."
}

# =============================================================================
# Naming & Tagging
# =============================================================================

variable "bucket_name_prefix" {
  type        = string
  description = "Optional prefix for the generated bucket name (e.g. your org or project). Ignored when custom_bucket_name is set."
  default     = null
}

variable "custom_bucket_name" {
  type        = string
  description = "Exact bucket name to use instead of the generated '<prefix>-<name>-<environment>' name"
  default     = null
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID that owns the bucket and KMS key. Defaults to the account of the current provider credentials."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

# =============================================================================
# Encryption
# =============================================================================

variable "kms_encryption_enabled" {
  type        = bool
  description = "Whether to enable SSE-KMS encryption on the bucket"
  default     = true
}

variable "aes256_encryption_enabled" {
  type        = bool
  description = "Whether to enable SSE-S3 (AES-256) encryption on the bucket. Only used when kms_encryption_enabled is false."
  default     = false
}

variable "use_custom_kms_key" {
  type        = bool
  description = "Use the KMS key provided in kms_key_arn instead of creating one. Only used when kms_encryption_enabled is true."
  default     = false
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of an existing KMS key for the bucket. Only used when kms_encryption_enabled and use_custom_kms_key are true."
  default     = ""
}

variable "manage_kms_key_policy" {
  type        = bool
  description = "When true (default), the module sets the policy on the KMS key it creates. Set to false when a parent module manages the key policy (e.g. via aws_kms_key_policy) to avoid conflicts."
  default     = true
}

variable "kms_external_encryption_account_ids" {
  type        = list(string)
  description = "External AWS account IDs allowed to use the module-created KMS key"
  default     = []
}

variable "kms_external_role_name" {
  type        = string
  description = "Name of the IAM role in each external account that may use the KMS key. Required when kms_external_encryption_account_ids is set and kms_external_use_root_account is false."
  default     = null
}

variable "kms_external_use_root_account" {
  type        = bool
  description = "Grant external KMS access to each external account's root principal instead of a named role"
  default     = false
}

variable "kms_external_allow_decrypt" {
  type        = bool
  description = "Allow external accounts kms:Decrypt and kms:DescribeKey in addition to kms:GenerateDataKey"
  default     = true
}

# =============================================================================
# Access Control
# =============================================================================

variable "block_public_acls" {
  type        = bool
  description = "Block public access granted through new ACLs. Forced to true when disable_acls is true."
  default     = true
}

variable "restrict_public_buckets" {
  type        = bool
  description = "Restrict access to buckets with public policies. Should generally be true unless the bucket must grant cross-account access via a public policy."
  default     = true
}

variable "disable_acls" {
  type        = bool
  description = "Disable ACLs and enforce bucket-owner object ownership (BucketOwnerEnforced)"
  default     = false
}

variable "control_object_ownership" {
  type        = bool
  description = "Explicitly configure object ownership using object_ownership"
  default     = false
}

variable "object_ownership" {
  type        = string
  description = "Object ownership setting: BucketOwnerPreferred, BucketOwnerEnforced, or ObjectWriter. Ignored when disable_acls is true."
  default     = "BucketOwnerPreferred"

  validation {
    condition     = contains(["BucketOwnerPreferred", "BucketOwnerEnforced", "ObjectWriter"], var.object_ownership)
    error_message = "object_ownership must be one of: BucketOwnerPreferred, BucketOwnerEnforced, ObjectWriter."
  }
}

# =============================================================================
# Bucket Policy
# =============================================================================

variable "attach_policy" {
  type        = bool
  description = "Whether to attach the custom bucket policy in bucket_policy"
  default     = false
}

variable "bucket_policy" {
  type        = string
  description = "A valid JSON bucket policy. Required when attach_policy is true."
  default     = null
}

variable "attach_deny_insecure_transport_policy" {
  type        = bool
  description = "Attach a policy statement that denies requests not made over TLS"
  default     = false
}

variable "cloudfront_oac_distribution_arns" {
  type        = list(string)
  description = "CloudFront distribution ARNs allowed to read this bucket via Origin Access Control. Grants cloudfront.amazonaws.com s3:GetObject on the bucket and, with SSE-KMS, use of the module-created key."
  default     = []
}

# =============================================================================
# Features
# =============================================================================

variable "versioning_enabled" {
  type        = bool
  description = "Whether to enable object versioning"
  default     = true
}

variable "eventbridge_notifications" {
  type        = bool
  description = "Send bucket event notifications to Amazon EventBridge"
  default     = false
}

variable "cors_configuration_enabled" {
  type        = bool
  description = "Whether to add a CORS configuration to the bucket"
  default     = false
}

variable "cors_allowed_methods" {
  type        = list(string)
  description = "Allowed CORS methods: GET, PUT, POST, DELETE, HEAD"
  default     = []
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "Allowed CORS origins"
  default     = []
}

variable "enable_access_logging" {
  type        = bool
  description = "Enable S3 server access logging for the bucket"
  default     = false
}

variable "access_logging_destination_bucket_name" {
  type        = string
  description = "Name of the bucket that receives access logs. Required when enable_access_logging is true. That bucket must allow logging.s3.amazonaws.com to write to it."
  default     = null
}

variable "access_logging_target_prefix" {
  type        = string
  description = "Key prefix for access log objects. Defaults to '<bucket-name>/'."
  default     = null
}

# =============================================================================
# Lifecycle
# =============================================================================

variable "lifecycle_rules" {
  type = list(object({
    id                           = string
    prefix                       = optional(string, "")
    expiration_days              = optional(number)
    noncurrent_expiration_days   = optional(number)
    expired_object_delete_marker = optional(bool, false)
    abort_incomplete_upload_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    noncurrent_transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  description = <<-EOT
    Prefix-scoped lifecycle rules. Each rule needs at least one action: an expiration, a transition, or abort_incomplete_upload_days.
    storage_class values: STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER, DEEP_ARCHIVE.
    Cannot be combined with auto_delete_files_rule_enabled or auto_delete_objects_rule_enabled.
  EOT
  default     = []

  validation {
    condition = alltrue(flatten([
      for r in var.lifecycle_rules : [
        for t in concat(r.transitions, r.noncurrent_transitions) :
        contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class)
      ]
    ]))
    error_message = "Transition storage_class must be one of STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, GLACIER_IR, GLACIER, DEEP_ARCHIVE."
  }
}

variable "auto_delete_files_rule_enabled" {
  type        = bool
  description = "Expire all objects after auto_delete_files_expiration_days"
  default     = false
}

variable "auto_delete_files_rule_id" {
  type        = string
  description = "ID of the expire-all-objects lifecycle rule"
  default     = "rule-1"
}

variable "auto_delete_files_expiration_days" {
  type        = number
  description = "Days after which all objects expire when auto_delete_files_rule_enabled is true"
  default     = 30
}

variable "auto_delete_objects_rule_enabled" {
  type        = bool
  description = "Expire objects carrying the auto_delete_objects_rule_tag_key/value tag"
  default     = false
}

variable "auto_delete_objects_rule_id" {
  type        = string
  description = "ID of the tag-scoped expiration lifecycle rule"
  default     = "rule-2"
}

variable "auto_delete_objects_rule_expiration_days" {
  type        = number
  description = "Days after which tagged objects (and their noncurrent versions) expire"
  default     = 30
}

variable "auto_delete_objects_rule_tag_key" {
  type        = string
  description = "Tag key that marks objects for auto-deletion"
  default     = "auto-delete"
}

variable "auto_delete_objects_rule_tag_value" {
  type        = string
  description = "Tag value that marks objects for auto-deletion"
  default     = "true"
}

# =============================================================================
# IRSA (IAM Roles for Service Accounts) - EKS pod access
# =============================================================================

variable "create_irsa_role" {
  type        = bool
  description = "Create an IAM role that EKS pods can assume (via IRSA) for read/write access to this bucket"
  default     = false
}

variable "oidc_provider_arn" {
  type        = string
  description = "ARN of the EKS cluster's IAM OIDC provider. Required when create_irsa_role is true."
  default     = ""
}

variable "oidc_provider_url" {
  type        = string
  description = "URL of the EKS cluster's OIDC issuer. Required when create_irsa_role is true."
  default     = ""
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace whose service accounts may assume the IRSA role"
  default     = "default"
}

variable "irsa_service_account_name" {
  type        = string
  description = "If set, only this service account in k8s_namespace may assume the IRSA role (recommended). If empty, any service account in the namespace may."
  default     = ""
}
