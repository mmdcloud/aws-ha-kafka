#!/bin/bash
# -----------------------------------------------------------------------------------------
# Zookeeper User Data Script
# This script sets up a Zookeeper node on Amazon Linux 2023
# -----------------------------------------------------------------------------------------

set -e  # Exit on error
set -x  # Print commands for debugging

# -----------------------------------------------------------------------------------------
# Configuration Variables (Passed from Terraform)
# -----------------------------------------------------------------------------------------
ZOOKEEPER_ID="${ZOOKEEPER_ID}"
ZOOKEEPER_SERVERS="${ZOOKEEPER_SERVERS}"
KAFKA_VERSION="${KAFKA_VERSION}"
SCALA_VERSION="${SCALA_VERSION}"
LOG_GROUP="${LOG_GROUP}"
AWS_REGION="${AWS_REGION}"

# Derived variables
KAFKA_FULL_VERSION="$SCALA_VERSION-$KAFKA_VERSION"
KAFKA_HOME="/opt/kafka"
ZOOKEEPER_DATA_DIR="/data/zookeeper"
ZOOKEEPER_LOG_DIR="/var/log/zookeeper"

# -----------------------------------------------------------------------------------------
# System Updates and Prerequisites
# -----------------------------------------------------------------------------------------
echo "==> Updating system packages..."
dnf update -y

echo "==> Installing required packages..."
dnf install -y \
    java-17-amazon-corretto \
    wget \
    curl \
    vim \
    net-tools \
    htop \
    jq \
    nc \
    amazon-cloudwatch-agent

# Verify Java installation
java -version

# -----------------------------------------------------------------------------------------
# Mount EBS Volume for Zookeeper Data
# -----------------------------------------------------------------------------------------
echo "==> Configuring EBS volume for Zookeeper data..."

# Wait for the volume to be attached
while [ ! -e /dev/xvdf ]; do
    echo "Waiting for EBS volume /dev/xvdf..."
    sleep 5
done

# Check if volume is already formatted
if ! blkid /dev/xvdf; then
    echo "Formatting EBS volume..."
    mkfs -t xfs /dev/xvdf
fi

# Create mount point
mkdir -p $ZOOKEEPER_DATA_DIR

# Mount the volume
mount /dev/xvdf $ZOOKEEPER_DATA_DIR

# Add to fstab for persistence
UUID=$(blkid -s UUID -o value /dev/xvdf)
if ! grep -q $UUID /etc/fstab; then
    echo "UUID=$UUID $ZOOKEEPER_DATA_DIR xfs defaults,nofail 0 2" >> /etc/fstab
fi

# Create zookeeper user
useradd -r -s /bin/false zookeeper || true

# Set ownership
chown -R zookeeper:zookeeper $ZOOKEEPER_DATA_DIR

# -----------------------------------------------------------------------------------------
# Download and Install Kafka (includes Zookeeper)
# -----------------------------------------------------------------------------------------
echo "==> Downloading Kafka $KAFKA_VERSION (includes Zookeeper)..."
cd /tmp
wget "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_$KAFKA_FULL_VERSION.tgz"

echo "==> Extracting Kafka..."
tar -xzf "kafka_$KAFKA_FULL_VERSION.tgz"
mv "kafka_$KAFKA_FULL_VERSION" $KAFKA_HOME

# Set ownership
chown -R zookeeper:zookeeper $KAFKA_HOME

# Create log directory
mkdir -p $ZOOKEEPER_LOG_DIR
chown -R zookeeper:zookeeper $ZOOKEEPER_LOG_DIR

# -----------------------------------------------------------------------------------------
# Configure Zookeeper
# -----------------------------------------------------------------------------------------
echo "==> Configuring Zookeeper..."

# Create myid file
mkdir -p $ZOOKEEPER_DATA_DIR/version-2
echo "$ZOOKEEPER_ID" > $ZOOKEEPER_DATA_DIR/myid
chown -R zookeeper:zookeeper $ZOOKEEPER_DATA_DIR

# Create Zookeeper configuration
cat > $KAFKA_HOME/config/zookeeper.properties <<EOF
# -----------------------------------------------------------------------------------------
# Zookeeper Configuration
# Generated on $(date)
# -----------------------------------------------------------------------------------------

# Data Directory
dataDir=$ZOOKEEPER_DATA_DIR

# Client Port
clientPort=2181

# Maximum number of client connections
maxClientCnxns=0

# Tick time in milliseconds
tickTime=2000

# Init limit for follower-leader sync
initLimit=10

# Sync limit for follower-leader communication
syncLimit=5

# Snapshot count
autopurge.snapRetainCount=3
autopurge.purgeInterval=24

# Performance tuning
preAllocSize=65536
snapCount=100000

# Admin server configuration
admin.enableServer=true
admin.serverPort=8080

# 4LW commands whitelist
4lw.commands.whitelist=srvr,stat,ruok,conf,isro

# Metrics
metricsProvider.className=org.apache.zookeeper.metrics.prometheus.PrometheusMetricsProvider
metricsProvider.httpPort=7000

# Zookeeper Ensemble Configuration
EOF

# Add server configurations
IFS=',' read -ra SERVERS <<< "$ZOOKEEPER_SERVERS"
for server in "${SERVERS[@]}"; do
    echo "$server" >> $KAFKA_HOME/config/zookeeper.properties
done

# -----------------------------------------------------------------------------------------
# Configure JVM Settings for Zookeeper
# -----------------------------------------------------------------------------------------
echo "==> Configuring JVM settings..."

# Get instance memory
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HEAP_SIZE=$((TOTAL_MEM / 2))g  # Use 50% of total memory for Zookeeper

cat > $KAFKA_HOME/bin/zookeeper-server-start-custom.sh <<EOF
#!/bin/bash
export KAFKA_HEAP_OPTS="-Xms$HEAP_SIZE -Xmx$HEAP_SIZE"
export KAFKA_JVM_PERFORMANCE_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:G1HeapRegionSize=16M"
export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:$KAFKA_HOME/config/log4j.properties"
export LOG_DIR=$ZOOKEEPER_LOG_DIR

$KAFKA_HOME/bin/zookeeper-server-start.sh $KAFKA_HOME/config/zookeeper.properties
EOF

chmod +x $KAFKA_HOME/bin/zookeeper-server-start-custom.sh

# -----------------------------------------------------------------------------------------
# Create Systemd Service
# -----------------------------------------------------------------------------------------
echo "==> Creating systemd service..."

cat > /etc/systemd/system/zookeeper.service <<EOF
[Unit]
Description=Apache Zookeeper
Documentation=http://zookeeper.apache.org
Requires=network.target
After=network.target

[Service]
Type=simple
User=zookeeper
Group=zookeeper
Environment="JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto"
Environment="LOG_DIR=$ZOOKEEPER_LOG_DIR"
ExecStart=$KAFKA_HOME/bin/zookeeper-server-start-custom.sh
ExecStop=$KAFKA_HOME/bin/zookeeper-server-stop.sh
Restart=on-failure
RestartSec=10s
LimitNOFILE=100000

# Hardening
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------------------------------------------------------------------
# Configure CloudWatch Agent
# -----------------------------------------------------------------------------------------
echo "==> Configuring CloudWatch Agent..."

cat > /opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "region": "$AWS_REGION",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "$ZOOKEEPER_LOG_DIR/zookeeper.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "zookeeper-$ZOOKEEPER_ID-main",
            "timezone": "UTC"
          },
          {
            "file_path": "$ZOOKEEPER_LOG_DIR/zookeeper.out",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "zookeeper-$ZOOKEEPER_ID-out",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Zookeeper",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {
            "name": "cpu_usage_idle",
            "rename": "CPU_IDLE",
            "unit": "Percent"
          },
          {
            "name": "cpu_usage_iowait",
            "rename": "CPU_IOWAIT",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60,
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {
            "name": "used_percent",
            "rename": "DISK_USED",
            "unit": "Percent"
          },
          {
            "name": "free",
            "rename": "DISK_FREE",
            "unit": "Gigabytes"
          }
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "$ZOOKEEPER_DATA_DIR"
        ]
      },
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MEM_USED",
            "unit": "Percent"
          }
        ],
        "metrics_collection_interval": 60
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "rename": "TCP_ESTABLISHED",
            "unit": "Count"
          }
        ],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}",
      "InstanceType": "\${aws:InstanceType}",
      "ZookeeperId": "$ZOOKEEPER_ID"
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json

# -----------------------------------------------------------------------------------------
# System Tuning for Zookeeper
# -----------------------------------------------------------------------------------------
echo "==> Applying system tuning..."

cat >> /etc/sysctl.conf <<EOF

# Zookeeper Performance Tuning
vm.swappiness=0
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_max_syn_backlog=4096
net.core.netdev_max_backlog=5000
fs.file-max=100000
EOF

sysctl -p

# Increase file descriptor limits
cat >> /etc/security/limits.conf <<EOF
zookeeper soft nofile 100000
zookeeper hard nofile 100000
zookeeper soft nproc 32768
zookeeper hard nproc 32768
EOF

# -----------------------------------------------------------------------------------------
# Health Check Script
# -----------------------------------------------------------------------------------------
echo "==> Creating health check script..."

cat > /usr/local/bin/zookeeper-health-check.sh <<EOF
#!/bin/bash

# Check if Zookeeper process is running
if ! pgrep -f QuorumPeerMain > /dev/null; then
    echo "ERROR: Zookeeper process not running"
    exit 1
fi

# Check if Zookeeper port is listening
if ! nc -z localhost 2181; then
    echo "ERROR: Zookeeper not listening on port 2181"
    exit 1
fi

# Send ruok command (Are you OK?)
RESPONSE=\$(echo "ruok" | nc localhost 2181)
if [ "\$RESPONSE" != "imok" ]; then
    echo "ERROR: Zookeeper health check failed. Response: \$RESPONSE"
    exit 1
fi

# Get Zookeeper status
STATUS=\$(echo "srvr" | nc localhost 2181 | grep Mode)
echo "OK: Zookeeper healthy - \$STATUS"
exit 0
EOF

chmod +x /usr/local/bin/zookeeper-health-check.sh

# -----------------------------------------------------------------------------------------
# Create Utility Scripts
# -----------------------------------------------------------------------------------------
echo "==> Creating utility scripts..."

# Script to get Zookeeper stats
cat > /usr/local/bin/zk-stats.sh <<EOF
#!/bin/bash
echo "=== Zookeeper Server Stats ==="
echo "srvr" | nc localhost 2181
echo ""
echo "=== Zookeeper Connections ==="
echo "cons" | nc localhost 2181
echo ""
echo "=== Zookeeper Watch Stats ==="
echo "wchs" | nc localhost 2181
EOF
chmod +x /usr/local/bin/zk-stats.sh

# Script to get Zookeeper configuration
cat > /usr/local/bin/zk-config.sh <<EOF
#!/bin/bash
echo "conf" | nc localhost 2181
EOF
chmod +x /usr/local/bin/zk-config.sh

# Script to check if node is leader
cat > /usr/local/bin/zk-is-leader.sh <<EOF
#!/bin/bash
echo "srvr" | nc localhost 2181 | grep "Mode: leader" > /dev/null
if [ \$? -eq 0 ]; then
    echo "This node is the LEADER"
    exit 0
else
    echo "This node is a FOLLOWER"
    exit 1
fi
EOF
chmod +x /usr/local/bin/zk-is-leader.sh

# -----------------------------------------------------------------------------------------
# Create Monitoring Cron Jobs
# -----------------------------------------------------------------------------------------
cat > /etc/cron.d/zookeeper-monitoring <<EOF
*/5 * * * * zookeeper /usr/local/bin/zookeeper-health-check.sh >> /var/log/zookeeper-health.log 2>&1
0 * * * * zookeeper /usr/local/bin/zk-stats.sh >> /var/log/zookeeper-stats.log 2>&1
EOF

# -----------------------------------------------------------------------------------------
# Start Zookeeper Service
# -----------------------------------------------------------------------------------------
echo "==> Starting Zookeeper service..."
systemctl daemon-reload
systemctl enable zookeeper
systemctl start zookeeper

# Wait for Zookeeper to start
sleep 20

# Verify Zookeeper is running
if systemctl is-active --quiet zookeeper; then
    echo "==> Zookeeper started successfully!"
    systemctl status zookeeper
    
    # Display node status
    sleep 10
    /usr/local/bin/zookeeper-health-check.sh
    echo ""
    echo "srvr" | nc localhost 2181
else
    echo "==> ERROR: Zookeeper failed to start"
    journalctl -u zookeeper -n 50
    exit 1
fi

# -----------------------------------------------------------------------------------------
# Create Data Backup Script
# -----------------------------------------------------------------------------------------
echo "==> Creating backup script..."

cat > /usr/local/bin/zk-backup.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/data/zookeeper/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
S3_BUCKET="${S3_BUCKET:-kafka-backups}"

mkdir -p $BACKUP_DIR

# Create snapshot
echo "Creating Zookeeper snapshot..."
tar -czf $BACKUP_DIR/zookeeper-$TIMESTAMP.tar.gz \
    -C /data/zookeeper \
    version-2 \
    myid

# Upload to S3 (if configured)
if command -v aws &> /dev/null; then
    echo "Uploading to S3..."
    aws s3 cp $BACKUP_DIR/zookeeper-$TIMESTAMP.tar.gz \
        s3://$S3_BUCKET/zookeeper/node-$ZOOKEEPER_ID/
fi

# Keep only last 7 backups locally
ls -t $BACKUP_DIR/zookeeper-*.tar.gz | tail -n +8 | xargs -r rm

echo "Backup complete: $BACKUP_DIR/zookeeper-$TIMESTAMP.tar.gz"
EOF

chmod +x /usr/local/bin/zk-backup.sh

# Schedule daily backups
cat >> /etc/cron.d/zookeeper-monitoring <<EOF
0 2 * * * zookeeper /usr/local/bin/zk-backup.sh >> /var/log/zookeeper-backup.log 2>&1
EOF

# -----------------------------------------------------------------------------------------
# Final Setup
# -----------------------------------------------------------------------------------------
echo "==> Zookeeper setup complete!"
echo "Zookeeper ID: $ZOOKEEPER_ID"
echo "Data Directory: $ZOOKEEPER_DATA_DIR"
echo "Log Directory: $ZOOKEEPER_LOG_DIR"
echo "Ensemble: $ZOOKEEPER_SERVERS"

# Display cluster status
echo ""
echo "==> Cluster Status:"
sleep 5
echo "stat" | nc localhost 2181 2>/dev/null || echo "Waiting for full cluster initialization..."

# Create completion marker
touch /var/log/zookeeper-setup-complete