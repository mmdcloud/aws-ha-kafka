#!/bin/bash
# -----------------------------------------------------------------------------------------
# Kafka Broker User Data Script
# This script sets up a Kafka broker on Amazon Linux 2023
# -----------------------------------------------------------------------------------------

set -e  # Exit on error
set -x  # Print commands for debugging

# -----------------------------------------------------------------------------------------
# Configuration Variables (Passed from Terraform)
# -----------------------------------------------------------------------------------------
BROKER_ID="${BROKER_ID}"
ZOOKEEPER_CONNECT="${ZOOKEEPER_CONNECT}"
KAFKA_VERSION="${KAFKA_VERSION}"
SCALA_VERSION="${SCALA_VERSION}"
LOG_GROUP="${LOG_GROUP}"
AWS_REGION="${AWS_REGION}"
REPLICATION_FACTOR="${REPLICATION_FACTOR}"
MIN_IN_SYNC_REPLICAS="${MIN_IN_SYNC_REPLICAS}"

# Derived variables
KAFKA_FULL_VERSION="$SCALA_VERSION-$KAFKA_VERSION"
KAFKA_HOME="/opt/kafka"
DATA_DIR="/data/kafka"
LOG_DIR="/var/log/kafka"

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
# Mount EBS Volume for Kafka Data
# -----------------------------------------------------------------------------------------
echo "==> Configuring EBS volume for Kafka data..."

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
mkdir -p $DATA_DIR

# Mount the volume
mount /dev/xvdf $DATA_DIR

# Add to fstab for persistence
UUID=$(blkid -s UUID -o value /dev/xvdf)
if ! grep -q $UUID /etc/fstab; then
    echo "UUID=$UUID $DATA_DIR xfs defaults,nofail 0 2" >> /etc/fstab
fi

# Set ownership
useradd -r -s /bin/false kafka || true
chown -R kafka:kafka $DATA_DIR

# -----------------------------------------------------------------------------------------
# Download and Install Kafka
# -----------------------------------------------------------------------------------------
echo "==> Downloading Kafka $KAFKA_VERSION..."
cd /tmp
wget "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_$KAFKA_FULL_VERSION.tgz"

echo "==> Extracting Kafka..."
tar -xzf "kafka_$KAFKA_FULL_VERSION.tgz"
mv "kafka_$KAFKA_FULL_VERSION" $KAFKA_HOME

# Set ownership
chown -R kafka:kafka $KAFKA_HOME

# Create log directory
mkdir -p $LOG_DIR
chown -R kafka:kafka $LOG_DIR

# -----------------------------------------------------------------------------------------
# Configure Kafka Server Properties
# -----------------------------------------------------------------------------------------
echo "==> Configuring Kafka broker..."

cat > $KAFKA_HOME/config/server.properties <<EOF
# -----------------------------------------------------------------------------------------
# Kafka Broker Configuration
# Generated on $(date)
# -----------------------------------------------------------------------------------------

# Broker ID
broker.id=$BROKER_ID

# Listener Configuration
listeners=PLAINTEXT://:9092,INTERNAL://:9093
advertised.listeners=PLAINTEXT://$(hostname -f):9092,INTERNAL://$(hostname -f):9093
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT
inter.broker.listener.name=INTERNAL

# Zookeeper Connection
zookeeper.connect=$ZOOKEEPER_CONNECT
zookeeper.connection.timeout.ms=18000

# Log Directories
log.dirs=$DATA_DIR/kafka-logs

# Replication Configuration
default.replication.factor=$REPLICATION_FACTOR
min.insync.replicas=$MIN_IN_SYNC_REPLICAS
num.replica.fetchers=4
replica.lag.time.max.ms=30000

# Log Retention Policy
log.retention.hours=168
log.retention.bytes=1073741824
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# Topic Configuration
num.partitions=3
auto.create.topics.enable=false
delete.topic.enable=true

# Network and I/O Configuration
num.network.threads=8
num.io.threads=16
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# Internal Topics
offsets.topic.replication.factor=$REPLICATION_FACTOR
transaction.state.log.replication.factor=$REPLICATION_FACTOR
transaction.state.log.min.isr=$MIN_IN_SYNC_REPLICAS

# Group Coordinator Configuration
group.initial.rebalance.delay.ms=3000

# Compression
compression.type=producer

# Performance Tuning
num.recovery.threads.per.data.dir=1
background.threads=10

# JMX Monitoring
jmx.port=9999

# Log Configuration
log.flush.interval.messages=10000
log.flush.interval.ms=1000

# Controller Configuration
controller.socket.timeout.ms=30000
replica.socket.timeout.ms=30000
replica.fetch.max.bytes=1048576
replica.fetch.wait.max.ms=500

# Metrics
metric.reporters=
metrics.num.samples=2
metrics.sample.window.ms=30000

# Quota Configuration
quota.window.num=11
quota.window.size.seconds=1

# SSL/TLS Configuration (if needed)
# ssl.keystore.location=/path/to/keystore
# ssl.keystore.password=password
# ssl.key.password=password
# ssl.truststore.location=/path/to/truststore
# ssl.truststore.password=password

EOF

# -----------------------------------------------------------------------------------------
# Configure JVM Settings
# -----------------------------------------------------------------------------------------
echo "==> Configuring JVM settings..."

# Get instance memory
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
HEAP_SIZE=$((TOTAL_MEM * 3 / 4))g  # Use 75% of total memory

cat > $KAFKA_HOME/bin/kafka-server-start-custom.sh <<EOF
#!/bin/bash
export KAFKA_HEAP_OPTS="-Xms$HEAP_SIZE -Xmx$HEAP_SIZE"
export KAFKA_JVM_PERFORMANCE_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:G1HeapRegionSize=16M -XX:MinMetaspaceFreeRatio=50 -XX:MaxMetaspaceFreeRatio=80"
export KAFKA_JMX_OPTS="-Dcom.sun.management.jmxremote=true -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.port=9999 -Dcom.sun.management.jmxremote.rmi.port=9999 -Djava.rmi.server.hostname=\$(hostname -f)"
export KAFKA_LOG4J_OPTS="-Dlog4j.configuration=file:$KAFKA_HOME/config/log4j.properties"

$KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties
EOF

chmod +x $KAFKA_HOME/bin/kafka-server-start-custom.sh

# -----------------------------------------------------------------------------------------
# Create Systemd Service
# -----------------------------------------------------------------------------------------
echo "==> Creating systemd service..."

cat > /etc/systemd/system/kafka.service <<EOF
[Unit]
Description=Apache Kafka Server
Documentation=http://kafka.apache.org/documentation.html
Requires=network.target
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto"
Environment="LOG_DIR=$LOG_DIR"
ExecStart=$KAFKA_HOME/bin/kafka-server-start-custom.sh
ExecStop=$KAFKA_HOME/bin/kafka-server-stop.sh
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
            "file_path": "$LOG_DIR/server.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "kafka-broker-$BROKER_ID-server",
            "timezone": "UTC"
          },
          {
            "file_path": "$LOG_DIR/controller.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "kafka-broker-$BROKER_ID-controller",
            "timezone": "UTC"
          },
          {
            "file_path": "$LOG_DIR/kafka-request.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "kafka-broker-$BROKER_ID-requests",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Kafka",
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
          "$DATA_DIR"
        ]
      },
      "diskio": {
        "measurement": [
          {
            "name": "io_time",
            "rename": "DISKIO_TIME",
            "unit": "Milliseconds"
          },
          {
            "name": "write_bytes",
            "rename": "DISKIO_WRITE_BYTES",
            "unit": "Bytes"
          },
          {
            "name": "read_bytes",
            "rename": "DISKIO_READ_BYTES",
            "unit": "Bytes"
          }
        ],
        "metrics_collection_interval": 60
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
          },
          {
            "name": "tcp_time_wait",
            "rename": "TCP_TIME_WAIT",
            "unit": "Count"
          }
        ],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}",
      "InstanceType": "\${aws:InstanceType}",
      "BrokerId": "$BROKER_ID"
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
# System Tuning for Kafka
# -----------------------------------------------------------------------------------------
echo "==> Applying system tuning..."

cat >> /etc/sysctl.conf <<EOF

# Kafka Performance Tuning
vm.swappiness=1
vm.dirty_ratio=80
vm.dirty_background_ratio=5
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_max_syn_backlog=4096
net.core.netdev_max_backlog=5000
fs.file-max=100000
EOF

sysctl -p

# Increase file descriptor limits
cat >> /etc/security/limits.conf <<EOF
kafka soft nofile 100000
kafka hard nofile 100000
kafka soft nproc 32768
kafka hard nproc 32768
EOF

# -----------------------------------------------------------------------------------------
# Health Check Script
# -----------------------------------------------------------------------------------------
echo "==> Creating health check script..."

cat > /usr/local/bin/kafka-health-check.sh <<'EOF'
#!/bin/bash

# Check if Kafka process is running
if ! pgrep -f kafka.Kafka > /dev/null; then
    echo "ERROR: Kafka process not running"
    exit 1
fi

# Check if Kafka port is listening
if ! nc -z localhost 9092; then
    echo "ERROR: Kafka not listening on port 9092"
    exit 1
fi

# Check broker registration in Zookeeper
BROKER_COUNT=$($KAFKA_HOME/bin/zookeeper-shell.sh ${ZOOKEEPER_CONNECT%%,*} <<< "ls /brokers/ids" 2>/dev/null | grep -o '\[.*\]')
if [ -z "$BROKER_COUNT" ]; then
    echo "ERROR: Cannot verify broker registration"
    exit 1
fi

echo "OK: Kafka broker healthy"
exit 0
EOF

chmod +x /usr/local/bin/kafka-health-check.sh

# -----------------------------------------------------------------------------------------
# Create Monitoring Cron Jobs
# -----------------------------------------------------------------------------------------
cat > /etc/cron.d/kafka-monitoring <<EOF
*/5 * * * * kafka /usr/local/bin/kafka-health-check.sh >> /var/log/kafka-health.log 2>&1
EOF

# -----------------------------------------------------------------------------------------
# Start Kafka Service
# -----------------------------------------------------------------------------------------
echo "==> Starting Kafka service..."
systemctl daemon-reload
systemctl enable kafka
systemctl start kafka

# Wait for Kafka to start
sleep 30

# Verify Kafka is running
if systemctl is-active --quiet kafka; then
    echo "==> Kafka broker started successfully!"
    systemctl status kafka
else
    echo "==> ERROR: Kafka broker failed to start"
    journalctl -u kafka -n 50
    exit 1
fi

# -----------------------------------------------------------------------------------------
# Final Setup
# -----------------------------------------------------------------------------------------
echo "==> Creating bootstrap topics (optional)..."

# Wait a bit more for broker to fully initialize
sleep 30

# Create test topic (optional)
$KAFKA_HOME/bin/kafka-topics.sh --create \
    --bootstrap-server localhost:9092 \
    --replication-factor $REPLICATION_FACTOR \
    --partitions 3 \
    --topic test-topic \
    --if-not-exists || true

echo "==> Kafka broker setup complete!"
echo "Broker ID: $BROKER_ID"
echo "Zookeeper: $ZOOKEEPER_CONNECT"
echo "Data Directory: $DATA_DIR"
echo "Log Directory: $LOG_DIR"

# Create completion marker
touch /var/log/kafka-setup-complete