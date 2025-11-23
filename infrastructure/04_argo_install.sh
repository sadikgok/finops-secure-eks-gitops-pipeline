#!/bin/bash
# ----------------------------------
# 04_argo_install.sh: ArgoCD/Kube-Admin Host Kurulumu (t4g.large)
# ----------------------------------

# 0. Genel Güncelleme ve Temel Araçlar (DNF/Amazon Linux)
sudo dnf update -y
sudo dnf install -y git curl wget unzip

# 1. AWS CLI v2 Kurulumu (Graviton/ARM64 Mimarisi)
echo "AWS CLI v2 Kurulumu Başlatılıyor (ARM64)..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
rm awscliv2.zip
rm -rf aws/

# 2. Kubernetes CLI Araçları (kubectl, eksctl, helm) - ARM64 Düzeltmesi
# (EKS kümesini yönetmek ve ArgoCD'yi kurmak için gereklidir)
echo "Kubernetes Araçları Kuruluyor (ARM64)..."

# 2.1. kubectl
K8S_VERSION=$(curl -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/$K8S_VERSION/bin/linux/arm64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 2.2. eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# 2.3. Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 3. ArgoCD CLI Kurulumu
echo "ArgoCD CLI Kuruluyor..."
sudo curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-arm64
sudo chmod +x /usr/local/bin/argocd

# 4. Kubeconfig Dosyasını Ayarlama (EKS'e Bağlanmak İçin)
# Bu komut, IAM rolü sayesinde otomatik olarak kimlik doğrulaması yapar ve kubeconfig dosyasını oluşturur.
# Ancak bu işlem EKS kümesi kurulduktan SONRA yapılmalıdır.
# Bu nedenle, bu komut *manuel olarak* veya Jenkins tarafından yürütülmelidir.
# echo "EKS bağlantısı için 'aws eks update-kubeconfig --name ${local.eks_cluster_name}' komutunu çalıştırın."

# Kurulum tamamlandı.
echo "ArgoCD Admin Host kurulumu tamamlandı."