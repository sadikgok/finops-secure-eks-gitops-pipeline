#!/bin/bash
# ============================================================
# 03_install.sh - Native Jenkins + Docker + DevOps Tools
# Target: Amazon Linux 2023 / ARM64
# ============================================================
set -euo pipefail

# Log everything (cloud-init + local log)
exec > >(tee -a /var/log/03_install.log | logger -t 03_install -s 2>/dev/console) 2>&1
trap 'echo "ERROR on line $LINENO. Exit code: $?"; exit 1' ERR

JENKINS_PORT=8080
SONAR_PORT=9000
DOCKER_NETWORK="sonarnet"
POSTGRES_PASSWORD="sonar_pass"
POSTGRES_USER="sonar"
POSTGRES_DB="sonar"

echo "=================================================================="
echo "Native Jenkins + Docker + DevOps Tools Installer (ARM64)"
echo "=================================================================="

echo "[0/9] Installing prerequisites..."
sudo dnf update -y
sudo dnf install -y wget curl unzip tar gzip git ca-certificates shadow-utils

# ----------------------------------
# 1. Java (Jenkins requirement)
# ----------------------------------
echo "[1/9] Installing Java (OpenJDK 17)..."
if ! java -version >/dev/null 2>&1; then
  sudo dnf install -y java-17-openjdk-devel
fi
java -version || true

# ----------------------------------
# 2. Docker
# ----------------------------------
echo "[2/9] Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  sudo dnf install -y docker
fi
sudo systemctl enable --now docker
docker --version || true

# Add ec2-user to docker group
sudo usermod -aG docker ec2-user || true

# ----------------------------------
# 3. Jenkins (Native) - with visibility
# ----------------------------------
echo "[3/9] Installing Jenkins (native package)..."
if ! rpm -q jenkins >/dev/null 2>&1; then
  echo "  - Adding Jenkins repo..."
  sudo wget -nv -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
  echo "  - Importing Jenkins key..."
  sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-key

  echo "  - Installing Jenkins..."
  # If this fails, you'll see the exact error in /var/log/03_install.log
  sudo dnf install -y jenkins
fi

sudo systemctl enable --now jenkins
sudo usermod -aG docker jenkins || true
sudo systemctl restart jenkins || true

echo "  - Jenkins status:"
sudo systemctl --no-pager status jenkins || true

# ----------------------------------
# 4. AWS CLI v2 (ARM64)
# ----------------------------------
echo "[4/9] Installing AWS CLI v2..."
if ! command -v aws >/dev/null 2>&1; then
  curl -fLs "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --update --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi
aws --version || true

# ----------------------------------
# 5. kubectl (pin major to your EKS, safer than "latest")
# ----------------------------------
echo "[5/9] Installing kubectl..."
if ! command -v kubectl >/dev/null 2>&1; then
  # Your cluster is 1.31 in Terraform. Keep kubectl close.
  KUBECTL_VERSION="v1.31.0"
  curl -fLs "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl" -o /tmp/kubectl
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
fi
kubectl version --client --short || true

# ----------------------------------
# 6. eksctl
# ----------------------------------
echo "[6/9] Installing eksctl..."
if ! command -v eksctl >/dev/null 2>&1; then
  curl -fLs "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_arm64.tar.gz" -o /tmp/eksctl.tar.gz
  sudo tar -xzf /tmp/eksctl.tar.gz -C /usr/local/bin eksctl
  rm -f /tmp/eksctl.tar.gz
fi
eksctl version || true

# ----------------------------------
# 7. helm (avoid pipe-to-bash)
# ----------------------------------
echo "[7/9] Installing helm..."
if ! command -v helm >/dev/null 2>&1; then
  HELM_VERSION="v3.16.3"
  curl -fLs "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz" -o /tmp/helm.tgz
  tar -xzf /tmp/helm.tgz -C /tmp
  sudo install -m 0755 /tmp/linux-arm64/helm /usr/local/bin/helm
  rm -rf /tmp/helm.tgz /tmp/linux-arm64
fi
helm version --short || true

# ----------------------------------
# 8. SonarQube + PostgreSQL (Docker)
# ----------------------------------
echo "[8/9] Setting up SonarQube + PostgreSQL..."
if ! grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -w vm.max_map_count=262144 >/dev/null || true

sudo docker network create "${DOCKER_NETWORK}" 2>/dev/null || true

sudo docker volume create sonar-db-data >/dev/null
sudo docker volume create sonar-data >/dev/null
sudo docker volume create sonar-logs >/dev/null
sudo docker volume create sonar-extensions >/dev/null

if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^sonarqube-db$"; then
  sudo docker run -d \
    --name sonarqube-db \
    --network "${DOCKER_NETWORK}" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -v sonar-db-data:/var/lib/postgresql/data \
    --restart always \
    postgres:13-alpine
fi

sleep 10

if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^sonar$"; then
  sudo docker run -d \
    --name sonar \
    --network "${DOCKER_NETWORK}" \
    -p ${SONAR_PORT}:9000 \
    -e SONAR_JDBC_URL="jdbc:postgresql://sonarqube-db:5432/${POSTGRES_DB}" \
    -e SONAR_JDBC_USERNAME="${POSTGRES_USER}" \
    -e SONAR_JDBC_PASSWORD="${POSTGRES_PASSWORD}" \
    -v sonar-data:/opt/sonarqube/data \
    -v sonar-logs:/opt/sonarqube/logs \
    -v sonar-extensions:/opt/sonarqube/extensions \
    --restart always \
    sonarqube:lts-community
fi

# ----------------------------------
# 9. Final info
# ----------------------------------
PUBLIC_IP=$(curl -s http://169.254.169.254/late_
