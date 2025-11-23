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
sudo dnf install docker -y
sudo systemctl enable docker
sudo systemctl start docker

# EC2 default kullanıcı ve Jenkins container için izinler
sudo mkdir -p /var/jenkins_home
sudo chown 1000:1000 /var/jenkins_home
sudo usermod -aG docker ec2-user

# ----------------------------------
# 2. Jenkins Docker Container Kurulumu (ARM64)
# ----------------------------------
sudo docker run -d \
  --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v /var/jenkins_home:/var/jenkins_home \
  --restart always \
  jenkins/jenkins:lts-jdk17

echo "Jenkins Docker container başlatıldı."

# ----------------------------------
# 3. Trivy Kurulumu (Güvenlik Tarama Aracı)
# ----------------------------------
sudo rpm -ivh https://github.com/aquasecurity/trivy/releases/download/v0.52.1/trivy_0.52.1_Linux-ARM64.rpm

# ----------------------------------
# 4. AWS CLI v2 Kurulumu (ARM64)
# ----------------------------------
sudo dnf install unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
rm awscliv2.zip
rm -rf aws/

# ----------------------------------
# 5. Kubernetes Araçları (kubectl, eksctl, helm)
# ----------------------------------

# 5.1 kubectl
K8S_VERSION=$(curl -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/$K8S_VERSION/bin/linux/arm64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 5.2 eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# 5.3 Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ----------------------------------
# 6. SonarQube ve PostgreSQL Container'ları
# ----------------------------------
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
# Jenkins başlangıç şifresi