################################################################################
# Required
################################################################################

variable "name" {
  description = "Function name, also used as the name or prefix of related resources"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,64}$", var.name))
    error_message = "name must be 1-64 characters: letters, numbers, hyphens and underscores."
  }
}

################################################################################
# Code
################################################################################

variable "filename" {
  description = "Path to a local deployment package (.zip). Set at most one of filename, s3_source or image_uri; with none, a placeholder stub is deployed"
  type        = string
  default     = null
}

variable "s3_source" {
  description = "Deployment package in S3: { bucket, key, object_version }"
  type = object({
    bucket         = string
    key            = string
    object_version = optional(string)
  })
  default = null
}

variable "image_uri" {
  description = "ECR image URI for a container image function (package_type Image). handler and runtime are ignored when set"
  type        = string
  default     = null
}

variable "source_code_hash" {
  description = "Base64 SHA256 of the package, used to trigger updates. Computed automatically for filename and the stub; set it for s3_source"
  type        = string
  default     = null
}

variable "handler" {
  description = "Function entrypoint. The default matches the built-in stub for both Node.js and Python runtimes"
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  description = "Lambda runtime, see https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html"
  type        = string
  default     = "nodejs22.x"
}

variable "ignore_code_changes" {
  description = "Ignore changes to the code (filename, s3_*, image_uri, source_code_hash) after creation, for when code is deployed outside Terraform (e.g. by CI). Changing this replaces the function resource in state; see README"
  type        = bool
  default     = false
}

################################################################################
# Function settings
################################################################################

variable "description" {
  description = "Function description"
  type        = string
  default     = null
}

variable "memory_size" {
  description = "Memory in MB (128-10240). CPU scales with memory"
  type        = number
  default     = 256

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240."
  }
}

variable "timeout" {
  description = "Timeout in seconds (1-900)"
  type        = number
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}

variable "architectures" {
  description = "Instruction set architecture: [\"x86_64\"] or [\"arm64\"]"
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition     = length(var.architectures) == 1 && contains(["x86_64", "arm64"], var.architectures[0])
    error_message = "architectures must be [\"x86_64\"] or [\"arm64\"]."
  }
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrency; -1 removes the limit, 0 disables invocations"
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions >= -1
    error_message = "reserved_concurrent_executions must be -1 or greater."
  }
}

variable "environment_variables" {
  description = "Environment variables for the function"
  type        = map(string)
  default     = {}
}

variable "layers" {
  description = "Lambda layer version ARNs (up to 5)"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.layers) <= 5
    error_message = "A function can use at most 5 layers."
  }
}

################################################################################
# IAM
################################################################################

variable "iam_policy_arns" {
  description = "Managed policy ARNs to attach to the function role"
  type        = list(string)
  default     = []
}

variable "iam_policy_documents" {
  description = "JSON policy documents added to the function role as inline policies"
  type        = list(string)
  default     = []
}

################################################################################
# Network
################################################################################

variable "network_config" {
  description = <<-EOT
    Run the function in a VPC. null (default) keeps it outside any VPC.
      subnet_ids, vpc_id: where to place the function's network interfaces
      enable_default_egress: allow outbound HTTPS (443) to 0.0.0.0/0 (default true)
      egress_rules: extra outbound rules, keyed by a unique name
      additional_security_group_ids: extra security groups to attach
  EOT
  type = object({
    subnet_ids            = list(string)
    vpc_id                = string
    enable_default_egress = optional(bool, true)
    egress_rules = optional(map(object({
      description = string
      from_port   = number
      to_port     = number
      protocol    = optional(string, "tcp")
      cidr_blocks = list(string)
    })), {})
    additional_security_group_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.network_config == null || try(length(var.network_config.subnet_ids) > 0 && var.network_config.vpc_id != "", false)
    error_message = "network_config needs at least one subnet_id and a vpc_id."
  }
}

################################################################################
# Logs
################################################################################

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days; 0 keeps logs forever"
  type        = number
  default     = 365

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a value CloudWatch Logs accepts (e.g. 7, 14, 30, 90, 365)."
  }
}

variable "log_kms_key_id" {
  description = "KMS key ARN to encrypt the log group. The key policy must allow the CloudWatch Logs service"
  type        = string
  default     = null
}

variable "log_subscription" {
  description = "Forward logs with a subscription filter: { destination_arn, role_arn (needed for Kinesis/Firehose), filter_pattern (\"\" = all) }"
  type = object({
    destination_arn = string
    role_arn        = optional(string)
    filter_pattern  = optional(string, "")
  })
  default = null
}

################################################################################
# Triggers, async invocation and alarms
################################################################################

variable "sqs_trigger" {
  description = <<-EOT
    Invoke the function from an SQS queue. The role gets receive/delete permissions on the queue,
    and kms:Decrypt on kms_key_arn when the queue uses a customer managed key.
  EOT
  type = object({
    queue_arn                          = string
    batch_size                         = optional(number, 10)
    maximum_batching_window_in_seconds = optional(number)
    enabled                            = optional(bool, true)
    report_batch_item_failures         = optional(bool, false)
    kms_key_arn                        = optional(string)
  })
  default = null

  validation {
    condition     = var.sqs_trigger == null || try(var.sqs_trigger.batch_size >= 1 && var.sqs_trigger.batch_size <= 10000, false)
    error_message = "sqs_trigger.batch_size must be between 1 and 10000."
  }
}

variable "schedule" {
  description = "Invoke the function on a schedule with an EventBridge rule: { expression = \"rate(5 minutes)\" or \"cron(...)\", description, enabled, input (JSON) }"
  type = object({
    expression  = string
    description = optional(string)
    enabled     = optional(bool, true)
    input       = optional(string)
  })
  default = null
}

variable "async_config" {
  description = <<-EOT
    Asynchronous invocation settings. null leaves the Lambda defaults.
      maximum_retry_attempts: 0-2
      maximum_event_age_in_seconds: 60-21600
      create_dead_letter_queue: create an encrypted SQS queue and send failed events to it
      dead_letter_queue_retention_seconds: message retention for that queue (default 14 days)
  EOT
  type = object({
    maximum_retry_attempts              = optional(number)
    maximum_event_age_in_seconds        = optional(number)
    create_dead_letter_queue            = optional(bool, false)
    dead_letter_queue_retention_seconds = optional(number, 1209600)
  })
  default = null

  validation {
    condition = var.async_config == null || (
      try(var.async_config.maximum_retry_attempts == null || (var.async_config.maximum_retry_attempts >= 0 && var.async_config.maximum_retry_attempts <= 2), false) &&
      try(var.async_config.maximum_event_age_in_seconds == null || (var.async_config.maximum_event_age_in_seconds >= 60 && var.async_config.maximum_event_age_in_seconds <= 21600), false)
    )
    error_message = "maximum_retry_attempts must be 0-2 and maximum_event_age_in_seconds 60-21600."
  }
}

variable "errors_alarm" {
  description = "CloudWatch alarm on the function's Errors metric. null (default) creates no alarm"
  type = object({
    threshold          = optional(number, 1)
    period             = optional(number, 300)
    evaluation_periods = optional(number, 1)
    treat_missing_data = optional(string, "notBreaching")
    alarm_actions      = optional(list(string), [])
    ok_actions         = optional(list(string), [])
  })
  default = null
}

variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default     = {}
}
