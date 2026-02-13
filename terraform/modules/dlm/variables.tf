variable "enabled" {
  description = "Whether to enable the DLM lifecycle policy"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the DLM lifecycle policy"
  type        = string
}

variable "description" {
  description = "Description of the DLM lifecycle policy"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the IAM role for DLM to use"
  type        = string
}

variable "state" {
  description = "State of the DLM lifecycle policy (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"
  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.state)
    error_message = "State must be either ENABLED or DISABLED."
  }
}

variable "resource_types" {
  description = "List of resource types to target (VOLUME or INSTANCE)"
  type        = list(string)
  default     = ["VOLUME"]
  validation {
    condition     = alltrue([for rt in var.resource_types : contains(["VOLUME", "INSTANCE"], rt)])
    error_message = "Resource types must be VOLUME or INSTANCE."
  }
}

variable "resource_locations" {
  description = "List of resource locations (CLOUD or OUTPOST)"
  type        = list(string)
  default     = ["CLOUD"]
}

variable "schedules" {
  description = "List of schedule configurations for the lifecycle policy"
  type = list(object({
    name = string
    create_rule = object({
      interval         = optional(number)
      interval_unit    = optional(string)
      times            = optional(list(string))
      cron_expression  = optional(string)
    })
    retain_rule = object({
      count         = optional(number)
      interval      = optional(number)
      interval_unit = optional(string)
    })
    tags_to_add            = optional(map(string))
    copy_tags              = optional(bool)
    cross_region_copy_rules = optional(list(object({
      target     = string
      encrypted  = optional(bool)
      cmk_arn    = optional(string)
      copy_tags  = optional(bool)
      retain_rule = optional(object({
        interval      = number
        interval_unit = string
      }))
    })))
    fast_restore_rule = optional(object({
      availability_zones = list(string)
      count             = optional(number)
      interval          = optional(number)
      interval_unit     = optional(string)
    }))
    share_rules = optional(list(object({
      target_accounts       = list(string)
      unshare_interval      = optional(number)
      unshare_interval_unit = optional(string)
    })))
  }))
}

variable "target_tags" {
  description = "Tags to identify target resources for the lifecycle policy"
  type        = map(string)
}

variable "common_tags_to_add" {
  description = "Common tags to add to all snapshots created by this policy"
  type        = map(string)
  default     = {}
}

variable "parameters" {
  description = "Additional parameters for the lifecycle policy"
  type = object({
    exclude_boot_volume = optional(bool)
    no_reboot          = optional(bool)
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to the DLM lifecycle policy resource"
  type        = map(string)
  default     = {}
}