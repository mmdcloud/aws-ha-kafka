# -----------------------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------------------
resource "aws_vpc" "kafka_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-kafka-vpc"
  }
}

resource "aws_internet_gateway" "kafka_igw" {
  vpc_id = aws_vpc.kafka_vpc.id

  tags = {
    Name = "${var.environment}-kafka-igw"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.kafka_vpc.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.environment}-kafka-private-subnet-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.kafka_vpc.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-kafka-public-subnet-${count.index + 1}"
    Tier = "public"
  }
}

# NAT Gateways for private subnets
resource "aws_eip" "nat_eips" {
  count  = 3
  domain = "vpc"

  tags = {
    Name = "${var.environment}-kafka-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "nat_gateways" {
  count         = 3
  allocation_id = aws_eip.nat_eips[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id

  tags = {
    Name = "${var.environment}-kafka-nat-gateway-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.kafka_igw]
}

# Route Tables
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.kafka_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kafka_igw.id
  }

  tags = {
    Name = "${var.environment}-kafka-public-rt"
  }
}

resource "aws_route_table" "private_route_tables" {
  count  = 3
  vpc_id = aws_vpc.kafka_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateways[count.index].id
  }

  tags = {
    Name = "${var.environment}-kafka-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public_associations" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_associations" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_tables[count.index].id
}

# -----------------------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------------------
resource "aws_security_group" "kafka_brokers_sg" {
  name        = "${var.environment}-kafka-brokers-sg"
  description = "Security group for Kafka brokers"
  vpc_id      = aws_vpc.kafka_vpc.id

  # Kafka broker port
  ingress {
    description = "Kafka broker communication"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Inter-broker communication
  ingress {
    description = "Inter-broker communication"
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    self        = true
  }

  # JMX monitoring
  ingress {
    description = "JMX monitoring"
    from_port   = 9999
    to_port     = 9999
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow communication with Zookeeper
  ingress {
    description     = "Zookeeper communication"
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [aws_security_group.zookeeper_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-kafka-brokers-sg"
  }
}

resource "aws_security_group" "zookeeper_sg" {
  name        = "${var.environment}-zookeeper-sg"
  description = "Security group for Zookeeper ensemble"
  vpc_id      = aws_vpc.kafka_vpc.id

  # Client port
  ingress {
    description     = "Zookeeper client port"
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [aws_security_group.kafka_brokers_sg.id]
  }

  # Follower port
  ingress {
    description = "Zookeeper follower port"
    from_port   = 2888
    to_port     = 2888
    protocol    = "tcp"
    self        = true
  }

  # Election port
  ingress {
    description = "Zookeeper election port"
    from_port   = 3888
    to_port     = 3888
    protocol    = "tcp"
    self        = true
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-zookeeper-sg"
  }
}

# -----------------------------------------------------------------------------------------
# IAM Roles and Policies
# -----------------------------------------------------------------------------------------
resource "aws_iam_role" "kafka_role" {
  name = "${var.environment}-kafka-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-kafka-ec2-role"
  }
}

resource "aws_iam_role_policy" "kafka_policy" {
  name = "${var.environment}-kafka-ec2-policy"
  role = aws_iam_role.kafka_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.kafka_backups.arn,
          "${aws_s3_bucket.kafka_backups.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "kafka_instance_profile" {
  name = "${var.environment}-kafka-instance-profile"
  role = aws_iam_role.kafka_role.name
}

# -----------------------------------------------------------------------------------------
# S3 Bucket for Backups
# -----------------------------------------------------------------------------------------
resource "aws_s3_bucket" "kafka_backups" {
  bucket = "${var.environment}-kafka-backups-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.environment}-kafka-backups"
  }
}

resource "aws_s3_bucket_versioning" "kafka_backups_versioning" {
  bucket = aws_s3_bucket.kafka_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kafka_backups_encryption" {
  bucket = aws_s3_bucket.kafka_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "kafka_backups_lifecycle" {
  bucket = aws_s3_bucket.kafka_backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------------------
# EBS Volumes for Kafka Data
# -----------------------------------------------------------------------------------------
resource "aws_ebs_volume" "kafka_data_volumes" {
  count             = var.kafka_broker_count
  availability_zone = data.aws_availability_zones.available.names[count.index % 3]
  size              = 500
  type              = "gp3"
  iops              = 3000
  throughput        = 125
  encrypted         = true

  tags = {
    Name   = "${var.environment}-kafka-broker-${count.index + 1}-data"
    Backup = "true"
  }
}

resource "aws_ebs_volume" "zookeeper_data_volumes" {
  count             = var.zookeeper_count
  availability_zone = data.aws_availability_zones.available.names[count.index % 3]
  size              = 100
  type              = "gp3"
  iops              = 3000
  encrypted         = true

  tags = {
    Name   = "${var.environment}-zookeeper-${count.index + 1}-data"
    Backup = "true"
  }
}

# -----------------------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "kafka_logs" {
  name              = "/aws/ec2/${var.environment}/kafka"
  retention_in_days = 7

  tags = {
    Name = "${var.environment}-kafka-logs"
  }
}

resource "aws_cloudwatch_log_group" "zookeeper_logs" {
  name              = "/aws/ec2/${var.environment}/zookeeper"
  retention_in_days = 7

  tags = {
    Name = "${var.environment}-zookeeper-logs"
  }
}

# -----------------------------------------------------------------------------------------
# Zookeeper Instances
# -----------------------------------------------------------------------------------------
resource "aws_instance" "zookeeper" {
  count                  = var.zookeeper_count
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.zookeeper_instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.private_subnets[count.index % 3].id
  vpc_security_group_ids = [aws_security_group.zookeeper_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.kafka_instance_profile.name

  user_data = base64encode(templatefile("${path.module}/scripts/zookeeper_userdata.sh", {
    ZOOKEEPER_ID      = count.index + 1
    ZOOKEEPER_SERVERS = join(",", [for i in range(var.zookeeper_count) : "server.${i + 1}=zookeeper-${i + 1}.kafka.local:2888:3888"])
    KAFKA_VERSION     = var.kafka_version
    SCALA_VERSION     = var.scala_version
    LOG_GROUP         = aws_cloudwatch_log_group.zookeeper_logs.name
    AWS_REGION        = var.aws_region
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = true
  }

  monitoring = var.enable_monitoring

  tags = {
    Name = "${var.environment}-zookeeper-${count.index + 1}"
    Role = "zookeeper"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_volume_attachment" "zookeeper_data_attachment" {
  count       = var.zookeeper_count
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.zookeeper_data_volumes[count.index].id
  instance_id = aws_instance.zookeeper[count.index].id
}

# -----------------------------------------------------------------------------------------
# Kafka Broker Instances
# -----------------------------------------------------------------------------------------
resource "aws_instance" "kafka_brokers" {
  count                  = var.kafka_broker_count
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.kafka_instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.private_subnets[count.index % 3].id
  vpc_security_group_ids = [aws_security_group.kafka_brokers_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.kafka_instance_profile.name

  user_data = base64encode(templatefile("${path.module}/scripts/kafka_userdata.sh", {
    BROKER_ID            = count.index + 1
    ZOOKEEPER_CONNECT    = join(",", [for i in range(var.zookeeper_count) : "zookeeper-${i + 1}.kafka.local:2181"])
    KAFKA_VERSION        = var.kafka_version
    SCALA_VERSION        = var.scala_version
    LOG_GROUP            = aws_cloudwatch_log_group.kafka_logs.name
    AWS_REGION           = var.aws_region
    REPLICATION_FACTOR   = min(var.kafka_broker_count, 3)
    MIN_IN_SYNC_REPLICAS = max(floor(var.kafka_broker_count / 2), 1)
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = true
  }

  monitoring = var.enable_monitoring

  tags = {
    Name = "${var.environment}-kafka-broker-${count.index + 1}"
    Role = "kafka-broker"
  }

  depends_on = [aws_instance.zookeeper]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "aws_volume_attachment" "kafka_data_attachment" {
  count       = var.kafka_broker_count
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.kafka_data_volumes[count.index].id
  instance_id = aws_instance.kafka_brokers[count.index].id
}

# -----------------------------------------------------------------------------------------
# Route53 Private Hosted Zone
# -----------------------------------------------------------------------------------------
resource "aws_route53_zone" "kafka_private_zone" {
  name = "kafka.local"

  vpc {
    vpc_id = aws_vpc.kafka_vpc.id
  }

  tags = {
    Name = "${var.environment}-kafka-private-zone"
  }
}

resource "aws_route53_record" "zookeeper_records" {
  count   = var.zookeeper_count
  zone_id = aws_route53_zone.kafka_private_zone.zone_id
  name    = "zookeeper-${count.index + 1}.kafka.local"
  type    = "A"
  ttl     = 300
  records = [aws_instance.zookeeper[count.index].private_ip]
}

resource "aws_route53_record" "kafka_broker_records" {
  count   = var.kafka_broker_count
  zone_id = aws_route53_zone.kafka_private_zone.zone_id
  name    = "kafka-broker-${count.index + 1}.kafka.local"
  type    = "A"
  ttl     = 300
  records = [aws_instance.kafka_brokers[count.index].private_ip]
}

# -----------------------------------------------------------------------------------------
# Application Load Balancer for Kafka (Optional)
# -----------------------------------------------------------------------------------------
resource "aws_lb" "kafka_nlb" {
  name               = "${var.environment}-kafka-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.private_subnets[*].id

  enable_deletion_protection = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.environment}-kafka-nlb"
  }
}

resource "aws_lb_target_group" "kafka_tg" {
  name     = "${var.environment}-kafka-tg"
  port     = 9092
  protocol = "TCP"
  vpc_id   = aws_vpc.kafka_vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 9092
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name = "${var.environment}-kafka-tg"
  }
}

resource "aws_lb_target_group_attachment" "kafka_tg_attachment" {
  count            = var.kafka_broker_count
  target_group_arn = aws_lb_target_group.kafka_tg.arn
  target_id        = aws_instance.kafka_brokers[count.index].id
  port             = 9092
}

resource "aws_lb_listener" "kafka_listener" {
  load_balancer_arn = aws_lb.kafka_nlb.arn
  port              = 9092
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kafka_tg.arn
  }
}

# -----------------------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "kafka_cpu_alarm" {
  count               = var.kafka_broker_count
  alarm_name          = "${var.environment}-kafka-broker-${count.index + 1}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors kafka broker cpu utilization"
  alarm_actions       = []

  dimensions = {
    InstanceId = aws_instance.kafka_brokers[count.index].id
  }

  tags = {
    Name = "${var.environment}-kafka-broker-${count.index + 1}-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "kafka_disk_alarm" {
  count               = var.kafka_broker_count
  alarm_name          = "${var.environment}-kafka-broker-${count.index + 1}-low-disk"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_free"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "This metric monitors kafka broker disk space"
  alarm_actions       = []

  dimensions = {
    InstanceId = aws_instance.kafka_brokers[count.index].id
    path       = "/data"
  }

  tags = {
    Name = "${var.environment}-kafka-broker-${count.index + 1}-disk-alarm"
  }
}

# -----------------------------------------------------------------------------------------
# DLM Lifecycle Policy for EBS Snapshots
# -----------------------------------------------------------------------------------------
resource "aws_iam_role" "dlm_lifecycle_role" {
  count = var.enable_backup ? 1 : 0
  name  = "${var.environment}-dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "dlm_lifecycle_policy" {
  count = var.enable_backup ? 1 : 0
  name  = "${var.environment}-dlm-lifecycle-policy"
  role  = aws_iam_role.dlm_lifecycle_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:EnableFastSnapshotRestores",
          "ec2:DescribeFastSnapshotRestores",
          "ec2:DisableFastSnapshotRestores",
          "ec2:CopySnapshot",
          "ec2:ModifySnapshotAttribute",
          "ec2:DescribeSnapshotAttribute"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*::snapshot/*"
      }
    ]
  })
}

resource "aws_dlm_lifecycle_policy" "kafka_backup_policy" {
  count              = var.enable_backup ? 1 : 0
  description        = "Kafka EBS backup policy"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Daily Kafka Backups"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 7
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
        Environment     = var.environment
      }

      copy_tags = true
    }

    target_tags = {
      Backup = "true"
    }
  }

  tags = {
    Name = "${var.environment}-kafka-backup-policy"
  }
}