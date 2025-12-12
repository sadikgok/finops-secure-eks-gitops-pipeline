#!/bin/bash
# ----------------------------------
# 05_monitoring_install.sh: Prometheus/Grafana Host (t4g.large / AL2023 ARM64)
# ----------------------------------
set -euo pipefail

exec > >(tee -a /var/log/05_monitoring_install.log | logger -t 05_monitoring_install -s 2>/dev/console) 2>&1
trap 'echo "ERROR on line $LINENO. Exit code: $?"; exit 1' ERR

echo "[0/4] System update & prerequisites..."
sudo dnf update -y
sudo dnf install -y docker git curl wget unzip

echo "[1/4] Enabling & starting Docker..."
sudo systemctl enable --now docker
sudo systemctl --no-pager status docker || true
docker --version || true

# Ensure ec2-user can run docker (will take effect on next login)
sudo usermod -aG docker ec2-user || true

echo "[2/4] Preparing directories..."
sudo mkdir -p /opt/monitoring/prometheus/config
sudo mkdir -p /opt/monitoring/grafana/data
# Grafana runs as UID 472 inside container
sudo chown -R 472:472 /opt/monitoring/grafana/data

echo "[3/4] Writing Prometheus config..."
sudo tee /opt/monitoring/prometheus/config/prometheus.yml >/dev/null <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF

echo "[4/4] Starting containers..."

# Optional: pin versions (recommended)
PROM_VERSION="v2.55.1"
GRAF_VERSION="11.3.0"
NODEEXP_VERSION="v1.8.2"

# Clean up old containers if exist (idempotent)
sudo docker rm -f prometheus grafana node_exporter >/dev/null 2>&1 || true

# Prometheus
sudo docker run -d \
  --name prometheus \
  --restart unless-stopped \
  -p 9090:9090 \
  -v /opt/monitoring/prometheus/config/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:${PROM_VERSION}

# Grafana
sudo docker run -d \
  --name grafana \
  --restart unless-stopped \
  -p 3000:3000 \
  -v /opt/monitoring/grafana/data:/var/lib/grafana \
  grafana/grafana:${GRAF_VERSION}

# Node Exporter
sudo docker run -d \
  --name node_exporter \
  --restart unless-stopped \
  --net="host" \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  quay.io/prometheus/node-exporter:${NODEEXP_VERSION} \
  --path.rootfs=/host

echo "✅ Monitoring containers started."
echo "Prometheus: http://<PUBLIC_IP>:9090"
echo "Grafana:    http://<PUBLIC_IP>:3000"
echo "Log:        /var/log/05_monitoring_install.log"
