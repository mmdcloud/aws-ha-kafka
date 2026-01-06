# EC2 Instance
resource "aws_instance" "instance" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  associate_public_ip_address = var.associate_public_ip_address
  user_data                   = var.user_data
  vpc_security_group_ids      = var.vpc_security_group_ids
  subnet_id                   = var.subnet_id
  iam_instance_profile        = var.instance_profile
  monitoring                  = var.monitoring
  dynamic "root_block_device" {
    for_each = var.root_block_device == null ? [] : [var.root_block_device]
    content {
      volume_type           = root_block_device.volume_type
      volume_size           = root_block_device.volume_size
      encrypted             = root_block_device.encrypted
      delete_on_termination = root_block_device.delete_on_termination
    }
  }
  
  tags = merge(
    {
      Name = var.name
    },
    var.tags
  )
}
