variable "name" {}
variable "ami_id" {}
variable "instance_type" {}
variable "key_name" {}
variable "associate_public_ip_address" {}
variable "user_data" {}
variable "subnet_id" {}
variable "vpc_security_group_ids" {}
variable "instance_profile" {}
variable "monitoring" {}
variable "tags" {}
variable "root_block_device" {
  type = object({
    volume_type = string
    volume_size = string
    encrypted = string
    delete_on_termination = string 
  })
}