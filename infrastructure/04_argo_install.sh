#!/bin/bash
# ----------------------------------
# 04_argo_install.sh: ArgoCD/Kube-Admin Host (t4g.large / AL2023 ARM64)
# ----------------------------------
set -euo pipefail

exec > >(tee -a /var/log/04_argo_install.log | logger -t 04_argo_install -s 2>/dev/console) 2>&1
trap 'echo "ERROR on line $LINENO. Exit code: $?"; exit 1' ERR

echo "[0/5] System update & prerequisites..."
sudo dnf update -y
sudo dnf install -y git curl wget unzip tar gzip ca-certificates

# ----------------------------------
# 1) AWS CLI v2 (ARM64)
# ----------------------------------
echo "[1/5] Installing AWS CLI v2..."
if ! command -v aws >/dev/null 2>&1; then
  curl -fLs "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --update --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi
aws --version || true

# ----------------------------------
# 2) kubectl (pin close to your EKS 1.31)
# ----------------------------------
echo "[2/5] Installing kubectl..."
if ! command -v kubectl >/dev/null 2>&1; then
  KUBECTL_VERSION="v1.31.0"
  curl -fLs "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl" -o /tmp/kubectl
  sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
fi
kubectl version --client --short || true

# ----------------------------------
# 3) eksctl
# ----------------------------------
echo "[3/5] Installing eksctl..."
if ! command -v eksctl >/dev/null 2>&1; then
  curl -fLs "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_arm64.tar.gz" -o /tmp/eksctl.tar.gz
  sudo tar -xzf /tmp/eksctl.tar.gz -C /usr/local/bin eksctl
  rm -f /tmp/eksctl.tar.gz
fi
eksctl version || true

# ----------------------------------
# 4) helm (no pipe-to-bash)
# ----------------------------------
echo "[4/5] Installing helm..."
if ! command -v helm >/dev/null 2>&1; then
  HELM_VERSION="v3.16.3"
  curl -fLs "https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz" -o /tmp/helm.tgz
  tar -xzf /tmp/helm.tgz -C /tmp
  sudo install -m 0755 /tmp/linux-arm64/helm /usr/local/bin/helm
  rm -rf /tmp/helm.tgz /tmp/linux-arm64
fi
helm version --short || true

# ----------------------------------
# 5) argocd CLI (pin or keep latest; here pin for stability)
# ----------------------------------
echo "[5/5] Installing argocd CLI..."
if ! command -v argocd >/dev/null 2>&1; then
  ARGOCD_VERSION="v2.12.6"
  curl -fLs "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-arm64" -o /tmp/argocd
  sudo install -m 0755 /tmp/argocd /usr/local/bin/argocd
  rm -f /tmp/argocd
fi
argocd version --client || true

echo "✅ ArgoCD Admin Host tools installed."
echo "Log: /var/log/04_argo_install.log"
echo "Next (after EKS): aws eks update-kubeconfig --name <cluster> --region <region>"
