#!/bin/bash
# ----------------------------------
# 05_monitoring_install.sh: Prometheus/Grafana Host Kurulumu (t4g.large)
# ----------------------------------
sudo dnf update -y
sudo dnf install -y docker git curl wget unzip

# Docker Kurulumu ve Başlatılması
sudo systemctl enable docker
sudo systemctl start docker

# Mevcut kullanıcıyı docker grubuna ekle
CURRENT_USER=$(whoami) 
sudo usermod -aG docker "$CURRENT_USER"

# 1. Prometheus ve Grafana Containerlarının Başlatılması
echo "Prometheus ve Grafana Konteynerları Başlatılıyor..."

# Prometheus yapılandırması için klasör oluştur (Kalıcılık için)
mkdir -p /home/ec2-user/prometheus/config
mkdir -p /home/ec2-user/grafana/data
chown -R 472:472 /home/ec2-user/grafana/data # Grafana'nın varsayılan UID/GID'si

# Prometheus yapılandırma dosyasını oluştur (Örnek)
cat <<EOF > /home/ec2-user/prometheus/config/prometheus.yml
global:
  scrape_interval: 15s 

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

# 1.1. Prometheus Container
sudo docker run -d \
    --name prometheus \
    --restart unless-stopped \
    -p 9090:9090 \
    -v /home/ec2-user/prometheus/config/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus:latest

# 1.2. Grafana Container
sudo docker run -d \
    --name grafana \
    --restart unless-stopped \
    -p 3000:3000 \
    -v /home/ec2-user/grafana/data:/var/lib/grafana \
    grafana/grafana:latest

# 2. Node Exporter Kurulumu (Bu makinenin metriklerini Prometheus'a göndermek için)
sudo docker run -d \
    --name node_exporter \
    --net="host" \
    --pid="host" \
    -v "/:/host:ro,rslave" \
    quay.io/prometheus/node-exporter:latest \
    --path.rootfs=/host

echo "Tüm monitoring araçları Docker konteynerlarında başlatıldı."
echo "Erişim: Grafana (3000), Prometheus (9090)"