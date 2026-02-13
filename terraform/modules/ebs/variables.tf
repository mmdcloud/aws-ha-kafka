variable "volumes" {
  description = "Map of EBS volumes to create and attach"
  type = map(object({
    availability_zone = string
    size              = number
    type              = optional(string)
    iops              = optional(number)
    throughput        = optional(number)
    encrypted         = optional(bool)
    kms_key_id        = optional(string)
    snapshot_id       = optional(string)
    device_name       = string
    instance_id       = string
    force_detach      = optional(bool)
    skip_destroy      = optional(bool)
    enable_backup     = optional(bool)
    tags              = optional(map(string))
  }))
  default = {}
}

variable "enable_backup" {
  description = "Default value for enabling backups on all volumes"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags to apply to all EBS volumes"
  type        = map(string)
  default     = {}
}