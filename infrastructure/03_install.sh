#!/bin/bash
# ============================================================
# 03_install.sh - Native Jenkins + Docker + DevOps Tools
# Target: Amazon Linux 2023 / ARM64
# ============================================================
set -euo pipefail

# --- CONFIGURATION
JENKINS_PORT=8080
SONAR_PORT=9000
DOCKER_NETWORK="sonarnet"
POSTGRES_PASSWORD="sonar_pass"
POSTGRES_USER="sonar"
POSTGRES_DB="sonar"

echo "=================================================================="
echo "Native Jenkins + Docker + DevOps Tools Installer (ARM64)"
echo "=================================================================="

# ----------------------------------
# 1. System Update
# ----------------------------------
echo "[1/9] Updating system..."
sudo dnf update -y

# ----------------------------------
# 2. Java Installation (Jenkins requirement)
# ----------------------------------
echo "[2/9] Installing Java (OpenJDK 17)..."
if ! java -version >/dev/null 2>&1; then
  sudo dnf install -y java-17-openjdk-devel
  echo "✓ Java installed"
else
  echo "✓ Java already installed"
fi

# ----------------------------------
# 3. Docker Installation
# ----------------------------------
echo "[3/9] Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
  sudo dnf install -y docker
  sudo systemctl enable docker
  sudo systemctl start docker
  echo "✓ Docker installed and started"
else
  echo "✓ Docker already installed"
  sudo systemctl enable docker
  sudo systemctl start docker
fi

# Add ec2-user to docker group
sudo usermod -aG docker ec2-user

# ----------------------------------
# 4. Jenkins Installation (Native Package)
# ----------------------------------
echo "[4/9] Installing Jenkins..."
if ! rpm -q jenkins >/dev/null 2>&1; then
  # Add Jenkins repository
  sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
  sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-key
  
  # Install Jenkins
  sudo dnf install -y jenkins
  
  # Configure Jenkins home
  sudo mkdir -p /var/lib/jenkins
  sudo chown -R jenkins:jenkins /var/lib/jenkins
  
  # Start Jenkins
  sudo systemctl enable jenkins
  sudo systemctl start jenkins
  
  echo "✓ Jenkins installed and started"
else
  echo "✓ Jenkins already installed"
  sudo systemctl enable jenkins
  sudo systemctl start jenkins
fi

# Add jenkins user to docker group (CRITICAL!)
echo "[4.1/9] Adding jenkins user to docker group..."
sudo usermod -aG docker jenkins

# Restart Jenkins to apply group membership
echo "[4.2/9] Restarting Jenkins to apply docker group..."
sleep 5
sudo systemctl restart jenkins

# Wait for Jenkins to initialize
echo "[4.3/9] Waiting for Jenkins to initialize (30 seconds)..."
sleep 30

# ----------------------------------
# 5. AWS CLI v2 (ARM64)
# ----------------------------------
echo "[5/9] Installing AWS CLI v2..."
if ! command -v aws >/dev/null 2>&1; then
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
  rm -rf /tmp/aws /tmp/awscliv2.zip
  echo "✓ AWS CLI installed"
else
  echo "✓ AWS CLI already installed"
fi

# ----------------------------------
# 6. Kubernetes Tools (kubectl, eksctl, helm)
# ----------------------------------
echo "[6/9] Installing Kubernetes tools..."

# kubectl
if ! command -v kubectl >/dev/null 2>&1; then
  K8S_VER=$(curl -s https://dl.k8s.io/release/stable.txt)
  curl -sL "https://dl.k8s.io/release/${K8S_VER}/bin/linux/arm64/kubectl" -o /tmp/kubectl
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
  echo "✓ kubectl installed"
else
  echo "✓ kubectl already installed"
fi

# eksctl
if ! command -v eksctl >/dev/null 2>&1; then
  curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | sudo tar -xz -C /usr/local/bin
  echo "✓ eksctl installed"
else
  echo "✓ eksctl already installed"
fi

# helm
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "✓ helm installed"
else
  echo "✓ helm already installed"
fi

# ----------------------------------
# 7. Trivy Docker Image
# ----------------------------------
echo "[7/9] Pulling Trivy Docker image..."
sudo docker pull aquasec/trivy:latest
echo "✓ Trivy image ready"

# ----------------------------------
# 8. SonarQube + PostgreSQL (Docker Containers)
# ----------------------------------
echo "[8/9] Setting up SonarQube + PostgreSQL..."

# Kernel parameter for SonarQube
if ! grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p >/dev/null
fi

# Create Docker network
sudo docker network create ${DOCKER_NETWORK} 2>/dev/null || echo "✓ Network ${DOCKER_NETWORK} already exists"

# PostgreSQL Container
if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^sonarqube-db$"; then
  sudo docker run -d \
    --name sonarqube-db \
    --network ${DOCKER_NETWORK} \
    -e POSTGRES_USER=${POSTGRES_USER} \
    -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    -e POSTGRES_DB=${POSTGRES_DB} \
    -v sonar-db-data:/var/lib/postgresql/data \
    --restart always \
    postgres:13-alpine
  echo "✓ PostgreSQL container started"
else
  echo "✓ PostgreSQL container already exists"
fi

# Wait for PostgreSQL to initialize
echo "  Waiting for PostgreSQL to initialize (15 seconds)..."
sleep 15

# SonarQube Container
if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^sonar$"; then
  sudo docker run -d \
    --name sonar \
    --network ${DOCKER_NETWORK} \
    -p ${SONAR_PORT}:9000 \
    -e SONAR_JDBC_URL="jdbc:postgresql://sonarqube-db:5432/${POSTGRES_DB}" \
    -e SONAR_JDBC_USERNAME="${POSTGRES_USER}" \
    -e SONAR_JDBC_PASSWORD="${POSTGRES_PASSWORD}" \
    -v sonar-data:/opt/sonarqube/data \
    -v sonar-logs:/opt/sonarqube/logs \
    -v sonar-extensions:/opt/sonarqube/extensions \
    --restart always \
    sonarqube:lts-community
  echo "✓ SonarQube container started"
else
  echo "✓ SonarQube container already exists"
fi

# ----------------------------------
# 9. Final Setup & Information
# ----------------------------------
echo "[9/9] Finalizing setup..."

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "<INSTANCE_IP>")

# Wait a bit more for Jenkins to fully initialize
sleep 10

echo ""
echo "=================================================================="
echo "✅ INSTALLATION COMPLETE!"
echo "=================================================================="
echo ""
echo "📦 Services:"
echo "  Jenkins:   http://${PUBLIC_IP}:${JENKINS_PORT}"
echo "  SonarQube: http://${PUBLIC_IP}:${SONAR_PORT}"
echo ""
echo "🔑 Jenkins Initial Password:"
echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
echo ""
echo "🔐 SonarQube Default Login:"
echo "  Username: admin"
echo "  Password: admin (change after first login)"
echo ""
echo "✅ Installed Tools:"
echo "  - Java:    $(java -version 2>&1 | head -n1)"
echo "  - Docker:  $(docker --version)"
echo "  - kubectl: $(kubectl version --client --short 2>/dev/null || echo 'installed')"
echo "  - eksctl:  $(eksctl version)"
echo "  - AWS CLI: $(aws --version)"
echo "  - helm:    $(helm version --short 2>/dev/null || echo 'installed')"
echo ""
echo "⚠️  IMPORTANT:"
echo "  - Jenkins user is now in docker group"
echo "  - Jenkins has been restarted to apply group membership"
echo "  - You can now run 'docker' commands from Jenkins pipelines"
echo ""
echo "🚀 Next Steps:"
echo "  1. Access Jenkins at http://${PUBLIC_IP}:${JENKINS_PORT}"
echo "  2. Get initial password: sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
echo "  3. Install suggested plugins"
echo "  4. Configure SonarQube token in Jenkins"
echo "  5. Add Docker Hub credentials"
echo ""
echo "=================================================================="