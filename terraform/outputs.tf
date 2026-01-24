output "vpc_id" {
  description = "VPC ID"
  value       = module.kafka_vpc.vpc_id
}

output "kafka_broker_private_ips" {
  description = "Private IPs of Kafka brokers"
  value       = module.kafka_brokers.private_ips
}

output "zookeeper_private_ips" {
  description = "Private IPs of Zookeeper nodes"
  value       = module.zookeeper.private_ips
}

output "kafka_nlb_dns" {
  description = "DNS name of the Kafka Network Load Balancer"
  value       = module.kafka_nlb.dns_name
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers connection string"
  value       = join(",", [for i in range(var.kafka_broker_count) : "kafka-broker-${i + 1}.kafka.local:9092"])
}

output "zookeeper_connect_string" {
  description = "Zookeeper connection string"
  value       = join(",", [for i in range(var.zookeeper_count) : "zookeeper-${i + 1}.kafka.local:2181"])
}

# output "s3_backup_bucket" {
#   description = "S3 bucket for Kafka backups"
#   value       = aws_s3_bucket.kafka_backups.id
# }