# -----------------------------------------------------------------------------------------
# EBS Volume Module
# -----------------------------------------------------------------------------------------

resource "aws_ebs_volume" "this" {
  for_each = var.volumes

  availability_zone = each.value.availability_zone
  size              = each.value.size
  type              = lookup(each.value, "type", "gp3")
  iops              = lookup(each.value, "iops", null)
  throughput        = lookup(each.value, "throughput", null)
  encrypted         = lookup(each.value, "encrypted", true)
  kms_key_id        = lookup(each.value, "kms_key_id", null)
  snapshot_id       = lookup(each.value, "snapshot_id", null)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name   = each.key
      Backup = lookup(each.value, "enable_backup", var.enable_backup) ? "true" : "false"
    }
  )
}

resource "aws_volume_attachment" "this" {
  for_each = var.volumes

  device_name = each.value.device_name
  volume_id   = aws_ebs_volume.this[each.key].id
  instance_id = each.value.instance_id

  # Optional parameters
  force_detach = lookup(each.value, "force_detach", false)
  skip_destroy = lookup(each.value, "skip_destroy", false)
}