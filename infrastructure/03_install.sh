#!/bin/bash
# ============================================================
# 03_install.sh - Jenkins Docker + DevOps Araçları (ARM64)
# Basit ve kullanıma hazır kurulum scripti
# ============================================================

set -e  # Hata durumunda scripti durdur

echo "======================================"
echo "Jenkins + DevOps Kurulumu Başlatılıyor"
echo "======================================"

# ----------------------------------
# 1. Sistem Güncelleme
# ----------------------------------
echo "[1/7] Sistem güncelleniyor..."
sudo dnf update -y

# ----------------------------------
# 2. Docker Kurulumu
# ----------------------------------
echo "[2/7] Docker kuruluyor..."
sudo dnf install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Jenkins için volume hazırlığı
sudo mkdir -p /var/jenkins_home
sudo chown -R 1000:1000 /var/jenkins_home
sudo chmod -R 755 /var/jenkins_home

# ----------------------------------
# 3. Jenkins Container Başlatma
# ----------------------------------
echo "[3/7] Jenkins container başlatılıyor..."
sudo docker run -d \
    --name jenkins \
    --user root \
    -p 8080:8080 -p 50000:50000 \
    -v /var/jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --restart always \
    jenkins/jenkins:lts-jdk17

echo "✓ Jenkins başlatıldı (Port: 8080)"

# ----------------------------------
# 4. Trivy Image'ini Hazırla
# ----------------------------------
echo "[4/7] Trivy docker image pull ediliyor..."
sudo docker pull aquasec/trivy:latest
echo "✓ Trivy hazır (Jenkins pipeline'dan kullanılabilir)"

# ----------------------------------
# 5. AWS CLI Kurulumu (Host)
# ----------------------------------
echo "[5/7] AWS CLI kuruluyor..."
sudo dnf install unzip -y
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
rm -rf awscliv2.zip aws/
echo "✓ AWS CLI kuruldu"

# ----------------------------------
# 6. SonarQube Hazırlık
# ----------------------------------
echo "[6/7] SonarQube için sistem yapılandırması..."
# Kernel parametresi (kalıcı)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p > /dev/null

# Docker network oluştur
sudo docker network create sonarnet 2>/dev/null || true

# PostgreSQL başlat
echo "  → PostgreSQL başlatılıyor..."
sudo docker run -d \
    --network sonarnet \
    --name sonarqube-db \
    -e POSTGRES_USER=sonar \
    -e POSTGRES_PASSWORD=sonar_pass \
    -e POSTGRES_DB=sonar \
    -v sonar-db-data:/var/lib/postgresql/data \
    --restart always \
    postgres:13-alpine

# PostgreSQL'in hazır olmasını bekle
echo "  → PostgreSQL hazırlanıyor (15 saniye)..."
sleep 15

# SonarQube başlat
echo "  → SonarQube başlatılıyor..."
sudo docker run -d \
    --network sonarnet \
    --name sonar \
    -p 9000:9000 \
    -e SONAR_JDBC_URL="jdbc:postgresql://sonarqube-db:5432/sonar" \
    -e SONAR_JDBC_USERNAME="sonar" \
    -e SONAR_JDBC_PASSWORD="sonar_pass" \
    -v sonar-data:/opt/sonarqube/data \
    -v sonar-logs:/opt/sonarqube/logs \
    -v sonar-extensions:/opt/sonarqube/extensions \
    --restart always \
    sonarqube:lts-community

echo "✓ SonarQube başlatıldı (Port: 9000)"

# ----------------------------------
# 7. Kurulum Bilgileri
# ----------------------------------
echo ""
echo "======================================"
echo "✓ KURULUM TAMAMLANDI!"
echo "======================================"
echo ""
echo "📦 Kurulu Servisler:"
echo "  • Jenkins:   http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "  • SonarQube: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9000"
echo ""
echo "🔑 Jenkins İlk Şifre:"
echo "  Aşağıdaki komutu çalıştırın:"
echo "  docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo ""
echo "🔐 SonarQube Varsayılan Giriş:"
echo "  Kullanıcı: admin"
echo "  Şifre: admin"
echo ""
echo "📝 Jenkins Pipeline'da Trivy Kullanımı:"
echo "  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \\"
echo "    aquasec/trivy:latest image --severity HIGH,CRITICAL <image-name>"
echo ""
echo "======================================"