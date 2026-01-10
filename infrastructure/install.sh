#!/usr/bin/env bash
set -euo pipefail

# Log her şey /var/log/user-data.log'a da düşsün
exec > >(tee -a /var/log/user-data.log) 2>&1

echo "==> Updating packages"
apt-get update -y
apt-get upgrade -y

echo "==> Installing base tools"
apt-get install -y \
  ca-certificates curl gnupg lsb-release unzip jq git \
  apt-transport-https software-properties-common

# -------------------------
# Docker + Compose
# -------------------------
echo "==> Installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# ubuntu kullanıcısını docker grubuna al (yeniden login sonrası aktif olur)
usermod -aG docker ubuntu || true

# -------------------------
# AWS CLI v2 (ARM64)
# -------------------------
echo "==> Installing AWS CLI v2"
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install || true

# -------------------------
# kubectl
# -------------------------
echo "==> Installing kubectl"
KUBECTL_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/arm64/kubectl"
chmod +x /usr/local/bin/kubectl

# -------------------------
# Helm
# -------------------------
echo "==> Installing Helm"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# -------------------------
# Trivy
# -------------------------
echo "==> Installing Trivy"
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /etc/apt/keyrings/trivy.gpg
echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/trivy.list
apt-get update -y
apt-get install -y trivy

# -------------------------
# Kubernetes (k3s) - single node, ARM64 friendly
# -------------------------
echo "==> Installing k3s"
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# k3s kubectl config: ubuntu kullanıcısı için kopyala
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# -------------------------
# Argo CD (k8s içine)
# -------------------------
echo "==> Installing Argo CD"
sudo -u ubuntu kubectl create namespace argocd || true
sudo -u ubuntu kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD UI'ya dışarıdan erişmek için (Lab amaçlı) NodePort açıyoruz.
# Prod'da Ingress + TLS önerilir.
sudo -u ubuntu kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}' || true

# -------------------------
# Jenkins + SonarQube (Docker)
# -------------------------
echo "==> Preparing Docker services (Jenkins + SonarQube)"

# SonarQube kernel param (Elasticsearch) ihtiyacı
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >/etc/sysctl.d/99-sonarqube.conf

mkdir -p /opt/devops-lab
cat >/opt/devops-lab/compose.yml <<'YAML'
services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - /usr/bin/docker:/usr/bin/docker
    restart: unless-stopped

  sonarqube:
    image: sonarqube:lts-community
    container_name: sonarqube
    ports:
      - "9000:9000"
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_extensions:/opt/sonarqube/extensions
      - sonar_logs:/opt/sonarqube/logs
    restart: unless-stopped

volumes:
  jenkins_home:
  sonar_data:
  sonar_extensions:
  sonar_logs:
YAML

docker compose -f /opt/devops-lab/compose.yml up -d

echo "==> Done."
echo "Jenkins:    http://<PUBLIC_IP>:8080"
echo "SonarQube:  http://<PUBLIC_IP>:9000"
echo "k3s:        kubectl get nodes"
echo "Argo CD:    kubectl -n argocd get svc argocd-server"

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
echo " (initial Argo CD admin password)"