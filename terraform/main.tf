# -----------------------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

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
module "kafka_vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "kafka-vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Name = "kafka-vpc"
  }
}

# -----------------------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------------------
module "kafka_brokers_sg" {
  source = "./modules/security-groups"
  name   = "kafka-brokers-sg"
  vpc_id = module.kafka_vpc.vpc_id
  ingress_rules = [
    {
      description = "Kafka broker communication"
      from_port   = 9092
      to_port     = 9092
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    },
    {
      description = "Inter-broker communication"
      from_port   = 9093
      to_port     = 9093
      protocol    = "tcp"
      self        = true
    },
    {
      description = "JMX monitoring"
      from_port   = 9999
      to_port     = 9999
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    },
    {
      description = "SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    },
    {
      description     = "Zookeeper communication"
      from_port       = 2181
      to_port         = 2181
      protocol        = "tcp"
      security_groups = [module.zookeeper_sg.id]
    }
  ]
  egress_rules = [
    {
      description     = "Allow outbound traffic to all"
      from_port       = 0
      to_port         = 0
      protocol        = "tcp"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
    }
  ]
  tags = {
    Name = "kafka-brokers-sg"
  }
}

module "zookeeper_sg" {
  source = "./modules/security-groups"
  name   = "zookeeper-sg"
  vpc_id = module.kafka_vpc.vpc_id
  ingress_rules = [
    {
      description     = "Zookeeper client port"
      from_port       = 2181
      to_port         = 2181
      protocol        = "tcp"
      security_groups = [module.kafka_brokers_sg.id]
    },
    {
      description = "Zookeeper follower port"
      from_port   = 2888
      to_port     = 2888
      protocol    = "tcp"
      self        = true
    },
    {
      description = "Zookeeper election port"
      from_port   = 3888
      to_port     = 3888
      protocol    = "tcp"
      self        = true
    },
    {
      description = "SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  ]
  egress_rules = [
    {
      description     = "Allow outbound traffic to all"
      from_port       = 0
      to_port         = 0
      protocol        = "tcp"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
    }
  ]
  tags = {
    Name = "kafka-brokers-sg"
  }
}

# -----------------------------------------------------------------------------------------
# IAM Roles and Policies
# -----------------------------------------------------------------------------------------
module "kafka_role" {
  source             = "./modules/iam"
  role_name          = "kafka-role"
  role_description   = "IAM role for Kafka"
  policy_name        = "kafka-role-policy"
  policy_description = "IAM policy for Kafka"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "ec2.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "ec2:DescribeInstances",
                  "ec2:DescribeTags",
                  "ec2:DescribeVolumes",
                  "ec2:CreateSnapshot",
                  "ec2:CreateTags",
                  "ec2:DescribeSnapshots"
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
            {
                "Action": [
                  "cloudwatch:PutMetricData",
                  "cloudwatch:GetMetricStatistics",
                  "cloudwatch:ListMetrics"
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
            {
                "Action": [
                  "logs:CreateLogGroup",
                  "logs:CreateLogStream",
                  "logs:PutLogEvents",
                  "logs:DescribeLogStreams"
                ],
                "Resource": "arn:aws:logs:*:*:*",
                "Effect": "Allow"
            },
            {
                "Action": [
                  "s3:GetObject",
                  "s3:ListBucket"
                ],
                "Resource": [
                    "${aws_s3_bucket.kafka_backups.arn}",
                    "${aws_s3_bucket.kafka_backups.arn}/*"
                ],
                "Effect": "Allow"
            }
        ]
    }
    EOF
}

resource "aws_iam_instance_profile" "kafka_instance_profile" {
  name = "kafka-instance-profile"
  role = module.kafka_role.name
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
module "kafka_logs" {
  source            = "./modules/cloudwatch/cloudwatch-log-groups"
  name              = "/aws/ec2/${var.environment}/kafka"
  retention_in_days = 7
  tags = {
    Name = "kafka-logs"
  }
}

module "zookeeper_logs" {
  source            = "./modules/cloudwatch/cloudwatch-log-groups"
  name              = "/aws/ec2/${var.environment}/zookeeper"
  retention_in_days = 7
  tags = {
    Name = "zookeeper-logs"
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
  subnet_id              = var.private_subnets[0]
  vpc_security_group_ids = [module.zookeeper_sg.id]
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
  subnet_id              = var.private_subnets[0]
  vpc_security_group_ids = [module.kafka_brokers_sg.id]
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
    vpc_id = module.kafka_vpc.id
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
  subnets            = var.private_subnets
  enable_deletion_protection       = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.environment}-kafka-nlb"
  }
}

resource "aws_lb_target_group" "kafka_tg" {
  name     = "${var.environment}-kafka-tg"
  port     = 9092
  protocol = "TCP"
  vpc_id   = module.kafka_vpc.id

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
# Alarm Configuration
# -----------------------------------------------------------------------------------------
module "alarm_notifications" {
  source     = "./modules/sns"
  topic_name = "kafka-cloudwatch-alarm-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
}

# -----------------------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------------------
module "kafka_cpu_alarm" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  count               = var.kafka_broker_count
  alarm_name          = "kafka-broker-${count.index + 1}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors kafka broker cpu utilization"
  alarm_actions       = [module.alarm_notifications.topic_arn]
  ok_actions          = [module.alarm_notifications.topic_arn]
  dimensions = {
    InstanceId = aws_instance.kafka_brokers[count.index].id
  }
}

module "kafka_disk_alarm" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  count               = var.kafka_broker_count
  alarm_name          = "kafka-broker-${count.index + 1}-low-disk"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_free"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "This metric monitors kafka broker disk space"
  alarm_actions       = [module.alarm_notifications.topic_arn]
  ok_actions          = [module.alarm_notifications.topic_arn]
  dimensions = {
    InstanceId = aws_instance.kafka_brokers[count.index].id
    path       = "/data"
  }
}

# -----------------------------------------------------------------------------------------
# DLM Lifecycle Policy for EBS Snapshots
# -----------------------------------------------------------------------------------------
module "dlm_lifecycle_role" {
  source             = "./modules/iam"
  role_name          = "dlm-lifecycle-role"
  role_description   = "IAM role for Data Lifecycle Manager"
  policy_name        = "dlm-lifecycle-policy"
  policy_description = "IAM policy for Data Lifecycle Manager"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "dlm.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
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
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
            {
                "Action": [
                  "ec2:CreateTags"
                ],
                "Resource": "arn:aws:ec2:*::snapshot/*",
                "Effect": "Allow"
            }
        ]
    }
    EOF
}

resource "aws_dlm_lifecycle_policy" "kafka_backup_policy" {
  count              = var.enable_backup ? 1 : 0
  description        = "Kafka EBS backup policy"
  execution_role_arn = module.dlm_lifecycle_role.arn
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
    Name = "kafka-backup-policy"
  }
}