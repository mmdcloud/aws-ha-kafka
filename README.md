# Apache Kafka Cluster on AWS - Terraform Infrastructure

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![Apache Kafka](https://img.shields.io/badge/Apache%20Kafka-Distributed%20Streaming-231F20?logo=apache-kafka)](https://kafka.apache.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> Production-ready Terraform configuration for deploying a highly available Apache Kafka cluster on AWS with ZooKeeper ensemble, complete monitoring, automated backups, and disaster recovery capabilities.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Module Structure](#module-structure)
- [Deployment](#deployment)
- [Monitoring & Alerts](#monitoring--alerts)
- [Backup & Recovery](#backup--recovery)
- [Security](#security)
- [Cost Optimization](#cost-optimization)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

This Terraform configuration deploys a production-grade Apache Kafka cluster on AWS with the following components:

- **Multi-node Kafka cluster** with configurable broker count
- **ZooKeeper ensemble** for cluster coordination (3-node recommended)
- **High availability** across multiple availability zones
- **Network Load Balancer** for client access
- **Automated backups** using AWS Data Lifecycle Manager
- **CloudWatch monitoring** with custom alarms
- **Private networking** with VPC isolation
- **IAM roles** with least-privilege access

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Cloud                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                      │  │
│  │                                                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │   AZ-1       │  │   AZ-2       │  │   AZ-3       │   │  │
│  │  │              │  │              │  │              │   │  │
│  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │   │  │
│  │  │ │  Kafka   │ │  │ │  Kafka   │ │  │ │  Kafka   │ │   │  │
│  │  │ │ Broker 1 │ │  │ │ Broker 2 │ │  │ │ Broker 3 │ │   │  │
│  │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │   │  │
│  │  │              │  │              │  │              │   │  │
│  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │   │  │
│  │  │ │ZooKeeper │ │  │ │ZooKeeper │ │  │ │ZooKeeper │ │   │  │
│  │  │ │  Node 1  │ │  │ │  Node 2  │ │  │ │  Node 3  │ │   │  │
│  │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │          Network Load Balancer (Internal)           │ │  │
│  │  │               Port 9092 (Kafka)                     │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐ │  │
│  │  │           Route53 Private Hosted Zone               │ │  │
│  │  │          kafka-broker-*.kafka.local                 │ │  │
│  │  │          zookeeper-*.kafka.local                    │ │  │
│  │  └─────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    Supporting Services                    │  │
│  │  • CloudWatch Logs & Alarms                              │  │
│  │  • S3 Bucket (Backups)                                   │  │
│  │  • SNS (Alarm Notifications)                             │  │
│  │  • DLM (Automated EBS Snapshots)                         │  │
│  │  • EBS Volumes (gp3, 500GB per broker)                   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## ✨ Features

### High Availability
- Multi-AZ deployment for fault tolerance
- Configurable replication factor and min in-sync replicas
- Automatic leader election via ZooKeeper
- Cross-zone load balancing

### Security
- Private subnet deployment (no public IPs)
- Security groups with least-privilege access
- Encrypted EBS volumes (AES-256)
- IAM roles with granular permissions
- VPC isolation with DNS resolution

### Monitoring
- CloudWatch Log Groups for Kafka and ZooKeeper
- CPU utilization alarms (>80%)
- Disk space alarms (<20% free)
- SNS notifications for critical alerts
- JMX metrics endpoint (port 9999)

### Backup & Disaster Recovery
- Automated EBS snapshots via Data Lifecycle Manager
- 7-day retention policy
- S3 bucket for application-level backups
- Versioning enabled on backup bucket
- Point-in-time recovery capability

### Performance
- gp3 EBS volumes with 3000 IOPS
- 500GB data volumes per Kafka broker
- 100GB data volumes per ZooKeeper node
- Configurable instance types
- Network Load Balancer for low-latency access

## 📦 Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- Valid AWS credentials configured

### AWS Requirements
- AWS Account with appropriate permissions
- EC2 key pair for SSH access
- Sufficient service quotas:
  - EC2 instances (recommended: 6+)
  - EBS volumes and IOPS
  - Elastic IPs (if using NAT gateways)
  - VPC resources

### Recommended Knowledge
- Apache Kafka fundamentals
- AWS networking concepts
- Terraform basics
- Linux system administration

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/kafka-terraform-aws.git
cd kafka-terraform-aws
```

### 2. Configure AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### 3. Create Terraform Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
environment            = "production"
aws_region            = "us-east-1"
azs                   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnets        = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets       = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Kafka Configuration
kafka_broker_count    = 3
kafka_instance_type   = "r6i.xlarge"
kafka_version         = "3.6.1"
scala_version         = "2.13"

# ZooKeeper Configuration
zookeeper_count       = 3
zookeeper_instance_type = "t3.medium"

# Security
key_pair_name         = "your-key-pair-name"
allowed_cidr_blocks   = ["10.0.0.0/16"]

# Monitoring
enable_monitoring     = true

# Backup
enable_backup         = true
```

### 4. Initialize Terraform

```bash
terraform init
```

### 5. Review the Execution Plan

```bash
terraform plan
```

### 6. Deploy the Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm.

**Deployment time:** Approximately 15-20 minutes

### 7. Verify the Deployment

```bash
# Get the NLB DNS name
terraform output nlb_dns_name

# Connect to a Kafka broker (requires bastion host or VPN)
ssh -i your-key.pem ec2-user@kafka-broker-1.kafka.local
```

## ⚙️ Configuration

### Core Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | `"production"` | Environment name (production, staging, dev) |
| `aws_region` | string | `"us-east-1"` | AWS region for deployment |
| `kafka_broker_count` | number | `3` | Number of Kafka brokers (min: 3 recommended) |
| `zookeeper_count` | number | `3` | Number of ZooKeeper nodes (must be odd) |
| `kafka_instance_type` | string | `"r6i.xlarge"` | EC2 instance type for Kafka brokers |
| `zookeeper_instance_type` | string | `"t3.medium"` | EC2 instance type for ZooKeeper |
| `kafka_version` | string | `"3.6.1"` | Apache Kafka version |
| `scala_version` | string | `"2.13"` | Scala version for Kafka binaries |
| `key_pair_name` | string | - | **Required:** EC2 key pair name |
| `allowed_cidr_blocks` | list(string) | - | **Required:** CIDR blocks for security groups |
| `enable_monitoring` | bool | `true` | Enable detailed CloudWatch monitoring |
| `enable_backup` | bool | `true` | Enable automated EBS snapshots |

### Network Configuration

```hcl
vpc_cidr         = "10.0.0.0/16"
azs              = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnets   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
```

### Instance Type Recommendations

| Environment | Kafka Broker | ZooKeeper | Notes |
|-------------|--------------|-----------|-------|
| **Development** | `t3.large` | `t3.small` | Cost-effective for testing |
| **Staging** | `m6i.xlarge` | `t3.medium` | Balanced compute and memory |
| **Production** | `r6i.xlarge` - `r6i.2xlarge` | `t3.medium` - `m6i.large` | Memory-optimized for high throughput |
| **High Traffic** | `r6i.4xlarge` | `m6i.xlarge` | Maximum performance |

## 📁 Module Structure

```
.
├── main.tf                          # Main configuration file
├── variables.tf                     # Variable definitions
├── outputs.tf                       # Output values
├── terraform.tfvars.example         # Example variables file
├── README.md                        # This file
│
├── modules/
│   ├── vpc/                         # VPC module
│   ├── security-groups/             # Security group module
│   ├── ec2/                         # EC2 instance module
│   ├── iam/                         # IAM roles and policies
│   ├── s3/                          # S3 bucket module
│   ├── sns/                         # SNS topic module
│   └── cloudwatch/
│       ├── cloudwatch-log-groups/   # Log group module
│       └── cloudwatch-alarm/        # Alarm module
│
└── scripts/
    ├── kafka_userdata.sh            # Kafka broker initialization
    └── zookeeper_userdata.sh        # ZooKeeper initialization
```

## 🚢 Deployment

### Pre-Deployment Checklist

- [ ] AWS credentials configured
- [ ] Required service quotas verified
- [ ] EC2 key pair created
- [ ] Variables file configured
- [ ] Terraform initialized
- [ ] Execution plan reviewed
- [ ] Backup strategy documented
- [ ] Monitoring contacts configured

### Deployment Steps

```bash
# 1. Validate configuration
terraform validate

# 2. Format code
terraform fmt -recursive

# 3. Plan with variable file
terraform plan -var-file="terraform.tfvars" -out=tfplan

# 4. Review the plan carefully
terraform show tfplan

# 5. Apply the plan
terraform apply tfplan

# 6. Save outputs
terraform output > deployment-outputs.txt
```

### Post-Deployment Verification

```bash
# Check Kafka broker status
ssh ec2-user@kafka-broker-1.kafka.local \
  "sudo systemctl status kafka"

# Check ZooKeeper ensemble
ssh ec2-user@zookeeper-1.kafka.local \
  "echo stat | nc localhost 2181"

# List Kafka topics
kafka-topics.sh --bootstrap-server kafka-nlb-xxx.elb.amazonaws.com:9092 --list

# Test connectivity
kafka-console-producer.sh \
  --bootstrap-server kafka-nlb-xxx.elb.amazonaws.com:9092 \
  --topic test-topic
```

## 📊 Monitoring & Alerts

### CloudWatch Metrics

The deployment includes the following CloudWatch monitoring:

1. **Kafka Broker Metrics**
   - CPU Utilization (threshold: >80%)
   - Disk Usage (threshold: <20% free)
   - Network I/O
   - Disk I/O operations

2. **ZooKeeper Metrics**
   - CPU Utilization
   - Memory Usage
   - Connection Count

### Log Groups

- `/aws/ec2/{environment}/kafka` - Kafka broker logs
- `/aws/ec2/{environment}/zookeeper` - ZooKeeper logs

### Alarm Notifications

All critical alarms send notifications to the configured SNS topic:

```hcl
# Update the email endpoint in main.tf
subscriptions = [
  {
    protocol = "email"
    endpoint = "your-email@example.com"
  }
]
```

### Accessing Logs

```bash
# View Kafka logs
aws logs tail /aws/ec2/production/kafka --follow

# View ZooKeeper logs
aws logs tail /aws/ec2/production/zookeeper --follow

# Query specific time range
aws logs filter-log-events \
  --log-group-name /aws/ec2/production/kafka \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR"
```

## 💾 Backup & Recovery

### Automated Backups

The infrastructure includes automated EBS snapshot backups via AWS Data Lifecycle Manager:

- **Frequency:** Daily at 03:00 UTC
- **Retention:** 7 days
- **Targets:** All EBS volumes tagged with `Backup = "true"`

### Manual Backup

```bash
# Create manual snapshot of Kafka data volume
aws ec2 create-snapshot \
  --volume-id vol-xxxxxxxxx \
  --description "Manual Kafka backup $(date +%Y%m%d)"

# List existing snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=tag:Environment,Values=production"
```

### Disaster Recovery Procedure

1. **Identify failed components**
   ```bash
   terraform state list | grep kafka_broker
   ```

2. **Restore from snapshot**
   ```bash
   # Create volume from snapshot
   aws ec2 create-volume \
     --snapshot-id snap-xxxxxxxxx \
     --availability-zone us-east-1a \
     --volume-type gp3
   
   # Attach to instance
   aws ec2 attach-volume \
     --volume-id vol-xxxxxxxxx \
     --instance-id i-xxxxxxxxx \
     --device /dev/xvdf
   ```

3. **Rebuild infrastructure**
   ```bash
   # Taint failed resources
   terraform taint 'module.kafka_brokers[0]'
   
   # Reapply
   terraform apply
   ```

### S3 Backup Bucket

Application-level backups can be stored in the S3 bucket:

```bash
# Upload topic configurations
kafka-configs.sh --describe --all --bootstrap-server localhost:9092 \
  > topic-configs.json

aws s3 cp topic-configs.json \
  s3://production-kafka-backups-{account-id}/configs/
```

## 🔒 Security

### Network Security

- **Private Subnets:** All Kafka and ZooKeeper instances deployed in private subnets
- **Security Groups:** Restrictive ingress rules, minimal egress
- **No Public IPs:** Instances not directly accessible from internet
- **VPC Isolation:** Dedicated VPC with DNS resolution enabled

### Security Group Rules

**Kafka Brokers:**
- Port 9092: Client connections (from allowed CIDR blocks)
- Port 9093: Inter-broker communication (self-referencing)
- Port 9999: JMX monitoring (from allowed CIDR blocks)
- Port 22: SSH (from allowed CIDR blocks)
- Port 2181: ZooKeeper client (from ZooKeeper SG)

**ZooKeeper:**
- Port 2181: Client connections (from Kafka SG)
- Port 2888: Follower connections (self-referencing)
- Port 3888: Leader election (self-referencing)
- Port 22: SSH (from allowed CIDR blocks)

### Data Encryption

- **At Rest:** EBS volumes encrypted with AWS KMS (AES-256)
- **In Transit:** Configure SSL/TLS for Kafka (see configuration guide)

### IAM Permissions

All instances use IAM roles with least-privilege permissions:

- EC2 describe operations
- CloudWatch metrics and logs
- S3 read access to backup bucket
- EBS snapshot creation
- No console or programmatic access

### Security Best Practices

1. **Rotate SSH Keys Regularly**
   ```bash
   # Update key pair
   terraform apply -var="key_pair_name=new-key-pair"
   ```

2. **Enable AWS Config**
   - Track configuration changes
   - Detect security misconfigurations

3. **Use AWS Secrets Manager**
   - Store sensitive configuration
   - Rotate credentials automatically

4. **Enable VPC Flow Logs**
   ```hcl
   # Add to VPC module
   enable_flow_log = true
   ```

5. **Implement MFA for SSH**
   - Configure PAM module for multi-factor authentication

## 💰 Cost Optimization

### Estimated Monthly Costs (us-east-1)

| Component | Specification | Monthly Cost |
|-----------|--------------|--------------|
| **3 × Kafka Brokers** | r6i.xlarge | ~$730 |
| **3 × ZooKeeper Nodes** | t3.medium | ~$100 |
| **EBS Volumes (Kafka)** | 3 × 500GB gp3 | ~$120 |
| **EBS Volumes (ZK)** | 3 × 100GB gp3 | ~$25 |
| **Network Load Balancer** | Internal NLB | ~$20 |
| **NAT Gateways** | 3 × NAT Gateway | ~$100 |
| **S3 Storage** | 100GB + requests | ~$5 |
| **CloudWatch** | Logs + Alarms | ~$20 |
| **Data Transfer** | Varies | ~$50 |
| **EBS Snapshots** | 7-day retention | ~$30 |
| **Total** | | **~$1,200/month** |

### Cost Reduction Strategies

1. **Use Single NAT Gateway** (Development/Staging)
   ```hcl
   single_nat_gateway = true
   one_nat_gateway_per_az = false
   ```
   **Savings:** ~$66/month

2. **Reduce Instance Sizes** (Non-Production)
   ```hcl
   kafka_instance_type = "t3.large"
   zookeeper_instance_type = "t3.small"
   ```
   **Savings:** ~$500/month

3. **Use Spot Instances** (Development only)
   ```hcl
   # Add to EC2 module
   instance_market_options = {
     market_type = "spot"
   }
   ```
   **Savings:** Up to 70%

4. **Optimize EBS Volumes**
   ```hcl
   # Reduce size for testing
   size = 100  # Instead of 500GB
   ```
   **Savings:** ~$80/month

5. **Disable Monitoring** (Non-Critical)
   ```hcl
   enable_monitoring = false
   ```
   **Savings:** ~$10/month

6. **Lifecycle Policy for S3**
   ```hcl
   # Transition to Glacier after 30 days
   transition = [{
     days          = 30
     storage_class = "GLACIER"
   }]
   ```
   **Savings:** ~$3/month per 100GB

## 🔧 Troubleshooting

### Common Issues

#### 1. Kafka Brokers Not Starting

**Symptoms:**
- Brokers fail health checks
- Can't connect to port 9092

**Diagnosis:**
```bash
# Check system logs
ssh ec2-user@kafka-broker-1.kafka.local \
  "sudo journalctl -u kafka -n 100"

# Check Kafka logs
ssh ec2-user@kafka-broker-1.kafka.local \
  "tail -f /opt/kafka/logs/server.log"
```

**Solutions:**
- Verify ZooKeeper connectivity
- Check disk space on data volumes
- Ensure security groups allow inter-broker communication
- Verify userdata script completed successfully

#### 2. ZooKeeper Ensemble Not Forming

**Symptoms:**
- ZooKeeper nodes in standalone mode
- Leader election fails

**Diagnosis:**
```bash
# Check ZooKeeper status
echo stat | nc zookeeper-1.kafka.local 2181

# Check ensemble configuration
ssh ec2-user@zookeeper-1.kafka.local \
  "cat /opt/kafka/config/zookeeper.properties"
```

**Solutions:**
- Verify myid file is correctly set
- Check firewall rules for ports 2888 and 3888
- Ensure Route53 DNS records are resolving

#### 3. EBS Volume Not Attaching

**Symptoms:**
- Data volume not mounted at /data
- Broker can't write data

**Diagnosis:**
```bash
# Check block devices
ssh ec2-user@kafka-broker-1.kafka.local "lsblk"

# Check mount points
ssh ec2-user@kafka-broker-1.kafka.local "df -h"

# Check device attachment
aws ec2 describe-volumes --volume-ids vol-xxxxxxxxx
```

**Solutions:**
- Verify volume is in same AZ as instance
- Check for device name conflicts
- Format volume if first time use
- Update fstab if persistence needed

#### 4. High CPU Utilization

**Symptoms:**
- CloudWatch alarms triggering
- Slow message processing

**Diagnosis:**
```bash
# Check broker metrics via JMX
kafka-run-class.sh kafka.tools.JmxTool \
  --jmx-url service:jmx:rmi:///jndi/rmi://kafka-broker-1.kafka.local:9999/jmxrmi \
  --object-name kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec
```

**Solutions:**
- Scale up instance type
- Add more brokers
- Optimize topic configurations (compression, retention)
- Review consumer lag

#### 5. Terraform State Lock

**Symptoms:**
- "Error locking state" message
- Can't run terraform operations

**Solution:**
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

### Debug Mode

Enable detailed logging:

```bash
# Terraform debug
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform-debug.log
terraform apply

# AWS CLI debug
aws ec2 describe-instances --debug
```

### Health Check Commands

```bash
# Overall cluster health
kafka-broker-api-versions.sh \
  --bootstrap-server kafka-nlb-xxx.elb.amazonaws.com:9092

# Topic health
kafka-topics.sh \
  --bootstrap-server kafka-nlb-xxx.elb.amazonaws.com:9092 \
  --describe

# Consumer group status
kafka-consumer-groups.sh \
  --bootstrap-server kafka-nlb-xxx.elb.amazonaws.com:9092 \
  --list
```

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

### Development Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and validation
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Code Standards

- Follow [Terraform Style Guide](https://www.terraform.io/docs/language/syntax/style.html)
- Use `terraform fmt` before committing
- Add comments for complex logic
- Update documentation for new features
- Include examples for new modules

### Testing

```bash
# Validate syntax
terraform validate

# Format code
terraform fmt -recursive

# Security scan
tfsec .

# Lint
tflint
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

### Getting Help

- **Documentation:** Check this README and inline comments
- **Issues:** [GitHub Issues](https://github.com/your-org/kafka-terraform-aws/issues)
- **Discussions:** [GitHub Discussions](https://github.com/your-org/kafka-terraform-aws/discussions)

### Reporting Issues

When reporting issues, please include:

1. Terraform version (`terraform version`)
2. AWS provider version
3. Complete error messages
4. Relevant log excerpts
5. Steps to reproduce

### Professional Support

For enterprise support, training, or custom implementations:
- Email: support@your-company.com
- Slack: [Community Slack](https://your-slack-invite-link.com)

---

## 📚 Additional Resources

### Apache Kafka Documentation
- [Official Documentation](https://kafka.apache.org/documentation/)
- [Operations Guide](https://kafka.apache.org/documentation/#operations)
- [Configuration Reference](https://kafka.apache.org/documentation/#configuration)

### AWS Documentation
- [EC2 Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-best-practices.html)
- [VPC User Guide](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [EBS Volume Types](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html)

### Terraform Resources
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Module Development](https://www.terraform.io/docs/language/modules/develop/index.html)

---

**Maintained by:** Your DevOps Team  
**Last Updated:** January 2026  
**Version:** 1.0.0
