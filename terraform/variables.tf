variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "kafka_version" {
  description = "Kafka version to install"
  type        = string
  default     = "3.6.1"
}

variable "public_subnets" {
  description = "Public Subnets"
  type        = list(string)
}

variable "private_subnets" {
  description = "Public Subnets"
  type        = list(string)
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)
}

variable "scala_version" {
  description = "Scala version"
  type        = string
  default     = "2.13"
}

variable "kafka_broker_count" {
  description = "Number of Kafka brokers"
  type        = number
  default     = 3
}

variable "kafka_instance_type" {
  description = "EC2 instance type for Kafka brokers"
  type        = string
  default     = "t3.large"
}

variable "zookeeper_count" {
  description = "Number of Zookeeper nodes"
  type        = number
  default     = 3
}

variable "zookeeper_instance_type" {
  description = "EC2 instance type for Zookeeper"
  type        = string
  default     = "t3.medium"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Kafka"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "key_pair_name" {
  description = "SSH key pair name"
  type        = string
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable automated EBS snapshots"
  type        = bool
  default     = true
}