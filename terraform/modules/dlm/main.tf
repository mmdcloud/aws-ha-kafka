# -----------------------------------------------------------------------------------------
# DLM Lifecycle Policy Module
# -----------------------------------------------------------------------------------------

resource "aws_dlm_lifecycle_policy" "this" {
  count              = var.enabled ? 1 : 0
  description        = var.description
  execution_role_arn = var.execution_role_arn
  state              = var.state

  policy_details {
    resource_types  = var.resource_types
    resource_locations = var.resource_locations

    dynamic "schedule" {
      for_each = var.schedules
      content {
        name = schedule.value.name

        create_rule {
          interval      = lookup(schedule.value.create_rule, "interval", null)
          interval_unit = lookup(schedule.value.create_rule, "interval_unit", null)
          times         = lookup(schedule.value.create_rule, "times", null)
          cron_expression = lookup(schedule.value.create_rule, "cron_expression", null)
        }

        retain_rule {
          count    = lookup(schedule.value.retain_rule, "count", null)
          interval = lookup(schedule.value.retain_rule, "interval", null)
          interval_unit = lookup(schedule.value.retain_rule, "interval_unit", null)
        }

        tags_to_add = merge(
          var.common_tags_to_add,
          lookup(schedule.value, "tags_to_add", {})
        )

        copy_tags = lookup(schedule.value, "copy_tags", true)

        dynamic "cross_region_copy_rule" {
          for_each = lookup(schedule.value, "cross_region_copy_rules", [])
          content {
            target    = cross_region_copy_rule.value.target
            encrypted = lookup(cross_region_copy_rule.value, "encrypted", true)
            cmk_arn   = lookup(cross_region_copy_rule.value, "cmk_arn", null)
            copy_tags = lookup(cross_region_copy_rule.value, "copy_tags", true)

            dynamic "retain_rule" {
              for_each = lookup(cross_region_copy_rule.value, "retain_rule", null) != null ? [cross_region_copy_rule.value.retain_rule] : []
              content {
                interval      = retain_rule.value.interval
                interval_unit = retain_rule.value.interval_unit
              }
            }
          }
        }

        dynamic "fast_restore_rule" {
          for_each = lookup(schedule.value, "fast_restore_rule", null) != null ? [schedule.value.fast_restore_rule] : []
          content {
            availability_zones = fast_restore_rule.value.availability_zones
            count             = lookup(fast_restore_rule.value, "count", null)
            interval          = lookup(fast_restore_rule.value, "interval", null)
            interval_unit     = lookup(fast_restore_rule.value, "interval_unit", null)
          }
        }

        dynamic "share_rule" {
          for_each = lookup(schedule.value, "share_rules", [])
          content {
            target_accounts = share_rule.value.target_accounts
            unshare_interval = lookup(share_rule.value, "unshare_interval", null)
            unshare_interval_unit = lookup(share_rule.value, "unshare_interval_unit", null)
          }
        }
      }
    }

    target_tags = var.target_tags

    dynamic "parameters" {
      for_each = var.parameters != null ? [var.parameters] : []
      content {
        exclude_boot_volume = lookup(parameters.value, "exclude_boot_volume", null)
        no_reboot          = lookup(parameters.value, "no_reboot", null)
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}