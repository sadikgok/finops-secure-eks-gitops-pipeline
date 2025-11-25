#!/bin/bash
# ============================================================
# 03_install.sh - ARM64 EC2 Üzerinde Jenkins Docker + DevOps Araçları
# ============================================================

# ----------------------------------
# 0. Sistem Güncelleme
# ----------------------------------
sudo dnf update -y

# ----------------------------------
# 1. Docker Kurulumu
# ----------------------------------
echo "1. Docker Kurulumu Başlatılıyor..."
sudo dnf install docker -y
sudo systemctl enable docker
sudo systemctl start docker

# Mevcut kullanıcıyı (ec2-user) docker grubuna ekle
sudo usermod -aG docker ec2-user

# Not: Jenkins kullanıcısının ID'si (1000) ile eşleşmesi için
# /var/jenkins_home dizinini oluştur ve izinleri ayarla
sudo mkdir -p /var/jenkins_home
# İzinleri EC2 user (geçici olarak) ve Jenkins user ID'sine verin
sudo chown 1000:1000 /var/jenkins_home

# ----------------------------------
# 2. Jenkins Docker Container Kurulumu (ARM64)
# ----------------------------------
echo "2. Jenkins Docker Container Başlatılıyor..."

# --user root: Docker komutlarını çalıştırmak için Container'a root izni ver
# -v /var/run/docker.sock:/var/run/docker.sock: Jenkins'in Host'taki Docker'ı kullanmasını sağlar (Docker-in-Docker)
sudo docker run -d \
    --name jenkins \
    --user root \
    -p 8080:8080 -p 50000:50000 \
    -v /var/jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --restart always \
    jenkins/jenkins:lts-jdk17 # ARM64 mimarisi bu imajı otomatik çeker

echo "Jenkins Docker container başlatıldı."

# ----------------------------------
# 3. Trivy Kurulumu (Host'a Kurulum: Jenkins Pipeline'da 'docker run' ile kullanmak için)
# ----------------------------------
echo "3. Trivy Kurulumu Başlatılıyor..."
# Trivy'nin resmi deposunu ekleyerek kurmak, PATH sorunlarını çözer
sudo rpm --import https://aquasecurity.github.io/trivy-repo/deb/public.key
sudo tee /etc/yum.repos.d/trivy.repo <<EOF
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/\$releasever/\$basearch/
gpgcheck=0
enabled=1
EOF
sudo dnf install -y trivy

# Trivy'yi /usr/local/bin'e kopyalamak, PATH sorunlarını çözer
sudo cp /usr/bin/trivy /usr/local/bin/trivy 
sudo chmod +x /usr/local/bin/trivy
echo "Trivy kurulumu tamamlandı ve Host'a (/usr/bin ve /usr/local/bin) yerleştirildi."

# ----------------------------------
# 4. AWS CLI v2 Kurulumu (ARM64)
# ----------------------------------
# Bu araç Host'a kurulmalıdır, çünkü Jenkins Container'ı AWS ile etkileşim kurmak için IAM rolünü kullanacaktır.
echo "4. AWS CLI Kurulumu Başlatılıyor..."
sudo dnf install unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
# /usr/local/bin'e kurmak, PATH'te bulunma şansını artırır
sudo ./aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
rm awscliv2.zip
rm -rf aws/

# ----------------------------------
# 5. Kubernetes Araçları (kubectl, eksctl, helm) - Host'a Kurulum
# ----------------------------------
# Bu araçlar Jenkins Container'ında değil, ArgoCD host'unda kurulu olmalıdır. 
# Eğer Jenkins'te K8S/EKS ile etkileşim kuracaksanız, bu adımları ArgoCD host'una taşıyabilirsiniz. 
# Eğer Jenkins'te kullanılacaksa (Genellikle ArgoCD host'una taşınır), bu kurulumlar doğrudur.

echo "5. Kubernetes Araçları Kuruluyor (ARM64)..."

# 5.1 kubectl (ARM64)
K8S_VERSION=$(curl -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/$K8S_VERSION/bin/linux/arm64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 5.2 eksctl (ARM64)
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# 5.3 Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ----------------------------------
# 6. SonarQube ve PostgreSQL Container'ları
# ----------------------------------
echo "6. SonarQube ve PostgreSQL Konteynerları Başlatılıyor..."
sudo docker network create sonarnet

# PostgreSQL (SonarQube için)
sudo sysctl -w vm.max_map_count=262144
sudo docker run -d --network sonarnet \
    --name sonarqube-db \
    -e POSTGRES_USER=sonar \
    -e POSTGRES_PASSWORD=sonar_pass \
    -e PGDATA=/var/lib/postgresql/data \
    postgres:13-alpine

# SonarQube
echo "10 saniye bekleme, PostgreSQL'in hazır olması için..."
sleep 10
sudo docker run -d --network sonarnet \
    --name sonar \
    --restart always \
    -p 9000:9000 \
    -e SONARQUBE_JDBC_URL="jdbc:postgresql://sonarqube-db:5432/sonar" \
    -e SONARQUBE_JDBC_USERNAME="sonar" \
    -e SONARQUBE_JDBC_PASSWORD="sonar_pass" \
    sonarqube:lts-community

echo "Kurulum tamamlandı. Jenkins Docker container ve diğer DevOps araçları hazır."