# 🚀 Enterprise-Grade CI/CD Pipeline with GitOps & Full Observability

> A hands-on DevOps project demonstrating production-ready CI/CD practices, GitOps deployment, multi-layer security scanning, and comprehensive monitoring infrastructure on AWS.

![Architecture](https://img.shields.io/badge/Architecture-Hybrid-blue)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitOps-green)
![Security](https://img.shields.io/badge/Security-Multi--Layer-red)
![Monitoring](https://img.shields.io/badge/Monitoring-Prometheus%20%2B%20Grafana-orange)
![IaC](https://img.shields.io/badge/IaC-Terraform-purple)

---

## ⚡ Executive Summary (1-Minute Read)

This project demonstrates:

* GitOps-driven CI/CD with strict separation of CI and CD
* Multi-layer security scanning (SAST + container)
* Kubernetes-native monitoring with Prometheus Operator
* Production-inspired infrastructure design decisions

**Target role:** DevOps / Platform / SRE Engineer

---

## 🔄 Pipeline Flow (Big Picture)

### Complete CI/CD Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Developer Push                                               │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Jenkins CI Pipeline                                          │
├─────────────────────────────────────────────────────────────────┤
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │  Checkout   │→ │ SonarQube   │→ │ Quality Gate│            │
│   │  (Git)      │  │ Analysis    │  │ (Block/Pass)│            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │  Trivy FS   │→ │ Docker Build│→ │ Trivy Image │            │
│   │  Scan       │  │             │  │ Scan        │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐                              │
│   │  Push to    │→ │ Update Git  │                              │
│   │  DockerHub  │  │ Manifest    │                              │
│   └─────────────┘  └─────────────┘                              │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Git Repository (Source of Truth)                            │
│   - deployment.yaml updated with new image tag                 │
│   - Commit: "Update image to sadikgok/app:BUILD_NUMBER"        │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. ArgoCD GitOps Engine                                         │
├─────────────────────────────────────────────────────────────────┤
│   - Detects manifest change                                     │
│   - Pulls desired state from Git                                │
│   - Applies to Kubernetes cluster                               │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Kubernetes Deployment                                        │
│   - Rolling update of application pods                          │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Monitoring & Observability                                   │
│   - Prometheus scrapes metrics                                  │
│   - Grafana visualizes system & app health                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🏗️ High-Level Architecture

The platform runs on AWS and is intentionally split into **two EC2 instances** to isolate CI/CD workloads from monitoring workloads.

* **CI/CD EC2:** Jenkins, SonarQube, ArgoCD, application runtime
* **Monitoring EC2:** Prometheus stack (Prometheus, Grafana, AlertManager)

This separation minimizes blast radius, avoids resource contention, and mirrors real-world enterprise designs.

---

## 🛠️ Infrastructure Breakdown

### CI/CD Infrastructure (Terraform – Automated)

The CI/CD environment is provisioned using **Terraform** to ensure reproducibility and version-controlled infrastructure.

**Key characteristics:**

* Automated EC2 provisioning
* Bootstrap via `user_data`
* Docker + K3s hybrid runtime

Components:

* Jenkins (CI orchestration)
* SonarQube (SAST)
* Trivy (filesystem & image scanning)
* ArgoCD (GitOps CD)
* K3s (single-node Kubernetes)

Jenkins handles **build and verification only**. It never directly deploys to Kubernetes.

---

### Monitoring Infrastructure (Manual – Learning Focused)

Monitoring is deployed on a **separate EC2 instance** and installed manually to gain deep operational understanding.

**Why manual?**

* Hands-on experience with Kubernetes primitives
* Better understanding of Prometheus Operator internals
* Explicit control over storage, retention, and resources

Components:

* Prometheus
* Grafana
* AlertManager
* Node Exporter
* Kube State Metrics

---

## 🔐 Security Implementation

Security is implemented as a **multi-layer pipeline concern**, not tied to a single component.

Layers include:

1. Static code analysis (SonarQube)
2. Quality gates
3. Filesystem vulnerability scanning (Trivy)
4. Container image scanning (Trivy)

Only artifacts that pass all security checks are promoted.

---

## 📊 Monitoring & Observability (Deep Dive)

The monitoring stack uses **Prometheus Operator** and Kubernetes-native `ServiceMonitor` resources.

* Automatic target discovery
* No manual Prometheus restarts
* Label-based metric selection

Grafana dashboards provide visibility into:

* EC2 system metrics
* Jenkins performance
* Kubernetes cluster health
* ArgoCD application sync status

---

## 🎓 Key Learnings

* Architectural decisions always involve trade-offs
* GitOps enforces discipline and auditability
* Monitoring must be isolated to remain reliable
* Resource contention becomes visible only when systems are observed

---

## ⚠️ Documented Trade-offs (Out of Scope by Design)

* Docker-outside-Docker used for simplicity and ARM64 compatibility
* Single-node Kubernetes clusters
* Auto-sync enabled in ArgoCD for learning velocity

These choices are deliberate and documented, not accidental limitations.

---

# 🚀 Enterprise-Grade CI/CD Pipeline with GitOps & Full Observability

> 📌 The following sections provide detailed implementation and setup instructions for each component described above. 
A hands-on DevOps project demonstrating production-ready CI/CD practices, GitOps deployment, multi-layer security scanning, and comprehensive monitoring infrastructure on AWS.

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [What Makes This Project Different](#-what-makes-this-project-different)
- [Technology Stack](#-technology-stack)
- [Infrastructure Setup](#-infrastructure-setup)
  - [CI/CD EC2 (Terraform)](#1-cicd-ec2-terraform-automated)
  - [Monitoring EC2 (Manual)](#2-monitoring-ec2-manual-setup)
- [Pipeline Flow](#-pipeline-flow)
- [Security Implementation](#-security-implementation)
- [Monitoring & Observability](#-monitoring--observability)
- [Key Learnings](#-key-learnings)
- [Known Limitations & Future Work](#-known-limitations--future-work)
- [Getting Started](#-getting-started)
- [Troubleshooting](#-troubleshooting)

---

## 🎯 Overview

This project implements a complete DevOps lifecycle from code commit to production deployment, featuring:

- ✅ **Automated CI/CD** with Jenkins, SonarQube, and Trivy
- ✅ **GitOps deployment** using ArgoCD (Jenkins builds, ArgoCD deploys)
- ✅ **Multi-layer security** (SAST + Filesystem + Container scanning)
- ✅ **Production-grade monitoring** on separate infrastructure
- ✅ **Infrastructure as Code** using Terraform
- ✅ **Hybrid architecture** (Docker + Kubernetes on same host)

**Key Principle:** Clear separation of concerns - Jenkins handles CI, ArgoCD handles CD. Git is the single source of truth.

---

## 🏗️ Architecture

### High-Level Infrastructure

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS Cloud Infrastructure                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────────────────┐    ┌─────────────────────────────┐  │
│  │  CI/CD EC2 (ARM64)         │    │  Monitoring EC2 (AMD64)     │  │
│  │  t3a.medium                │    │  t3.medium                  │  │
│  ├────────────────────────────┤    ├─────────────────────────────┤  │
│  │                            │    │                             │  │
│  │  🐳 Docker Engine          │    │  ☸️  K3s Cluster            │  │
│  │    ├─ Jenkins              │◄───┤    ├─ Prometheus Stack     │  │
│  │    ├─ SonarQube            │    │    │  ├─ Prometheus         │  │
│  │    └─ Node Exporter        │    │    │  ├─ Grafana            │  │
│  │                            │    │    │  ├─ AlertManager       │  │
│  │  ☸️  K3s Cluster           │    │    │  ├─ Node Exporter      │  │
│  │    ├─ ArgoCD               │    │    │  └─ Kube State Metrics │  │
│  │    └─ Next.js App (Pods)   │    │                             │  │
│  │                            │    │  Scrapes metrics from:       │  │
│  └────────────────────────────┘    │  ├─ Jenkins (app metrics)   │  │
│           │                        │  ├─ Jenkins EC2 (sys metrics)│  │
│           ▼                        │  └─ Itself (sys metrics)     │  │
│  ┌────────────────────────┐        └─────────────────────────────┘  │
│  │   GitHub Repository    │                                          │
│  │  (Source of Truth)     │                                          │
│  └────────────────────────┘                                          │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Two Separate EC2 Instances?

**Design Decision: Isolation & Blast Radius Management**

1. **Blast Radius Minimization**
   - If monitoring breaks, CI/CD continues
   - If CI/CD breaks, monitoring still observes
   - Can upgrade/restart one without affecting the other

2. **Resource Contention Avoidance**
   - Prometheus is CPU/RAM intensive during scraping
   - Jenkins builds consume significant resources
   - SonarQube analysis is memory-heavy
   - Separation prevents OOM (Out of Memory) kills

3. **Production-Like Architecture**
   - Simulates real enterprise setups
   - Demonstrates understanding of operational concerns
   - Shows infrastructure design maturity

---

## 💡 What Makes This Project Different

### 1. **Hybrid Architecture (Conscious Design)**

```
CI/CD EC2:
├─ Docker Engine (for Jenkins, SonarQube)
├─ K3s Cluster (for ArgoCD, Application)
└─ Why? Legacy tools (Jenkins, SonarQube) run well in Docker
         Modern apps run in Kubernetes

Monitoring EC2:
├─ K3s Cluster ONLY (for Prometheus Stack)
└─ Why? Cloud-native monitoring, Helm charts, ServiceMonitors
```

**Not a mistake, but a deliberate choice based on tool characteristics.**

### 2. **Docker-outside-Docker (DooD), Not DinD**

```yaml
Jenkins Container:
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock  # Access host Docker
    - /usr/bin/docker:/usr/bin/docker            # Use host Docker binary

Why DooD?
  ✅ Lightweight (no nested Docker engine)
  ✅ Better performance
  ✅ Standard workaround for ARM64 compatibility
  ⚠️  Security trade-off: Socket access = root-level power
```

**Risk is documented and accepted for learning environment.**

### 3. **True GitOps Implementation**

```
Traditional Approach (Anti-pattern):
  Jenkins → kubectl apply → Kubernetes
  ❌ Jenkins has cluster credentials
  ❌ No audit trail
  ❌ Difficult rollback

Our Approach (GitOps):
  Jenkins → Update Git manifest → ArgoCD pulls → Kubernetes
  ✅ Git is source of truth
  ✅ Full audit trail (git log)
  ✅ Easy rollback (git revert)
  ✅ Jenkins never touches cluster
```

### 4. **Kubernetes-Native Monitoring**

```
Traditional: additionalScrapeConfigs (manual Prometheus config)
Our Way: ServiceMonitors (Kubernetes-native, operator-managed)

Benefits:
  ✅ Auto-discovery
  ✅ No Prometheus restart needed
  ✅ Label-based selection
  ✅ Industry standard (used in production)
```

---

## 🛠️ Technology Stack

### CI/CD Infrastructure (Terraform Automated)

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Jenkins** | CI Orchestration | Docker container, LTS JDK17 |
| **SonarQube** | Static Code Analysis | Docker container, LTS Community |
| **Trivy** | Security Scanning | Ephemeral containers via DooD |
| **ArgoCD** | GitOps CD | K3s pod, auto-sync enabled |
| **K3s** | Kubernetes | Single-node, ARM64 compatible |
| **Docker** | Container Runtime | Engine + DooD for builds |

### Monitoring Infrastructure (Manual Setup)

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **Prometheus** | Metrics Collection | 15d retention, 10GB storage |
| **Grafana** | Visualization | Pre-configured dashboards |
| **AlertManager** | Alert Routing | Email/Slack ready |
| **Node Exporter** | System Metrics | On both EC2 instances |
| **Kube State Metrics** | K8s Metrics | Cluster resource monitoring |

### Application Stack

| Component | Purpose | Details |
|-----------|---------|---------|
| **Next.js 15** | Frontend Application | Modern React framework |
| **Docker** | Containerization | Multi-stage build |
| **DockerHub** | Image Registry | Public repository |

---

## 🚀 Infrastructure Setup

### 1. CI/CD EC2 (Terraform Automated)

**Why Terraform?** 
- Infrastructure as Code (reproducible, version-controlled)
- Automated bootstrap via `user_data`
- Fast setup (5-10 minutes)

**What Gets Installed?**

```bash
# Via Terraform user_data script (install.sh):
├─ Docker Engine
├─ K3s (Kubernetes)
├─ Jenkins (Docker container)
├─ SonarQube (Docker container)
├─ Node Exporter (Docker container)
├─ ArgoCD (K3s pod)
├─ Trivy (via apt)
├─ kubectl, helm, aws-cli
└─ Application manifests
```

**Deployment:**

```bash
# Clone repository
git clone https://github.com/sadikgok/finops-secure-eks-gitops-pipeline.git
cd finops-secure-eks-gitops-pipeline/terraform

# Initialize and apply
terraform init
terraform plan
terraform apply -auto-approve

# Monitor installation
ssh -i key.pem ubuntu@<EC2-IP>
tail -f /var/log/user-data.log
```

**Post-Installation:**

```bash
# Verify Docker containers
docker ps  # Should show: jenkins, sonarqube, node-exporter

# Verify K3s pods
kubectl get pods -A  # Should show: argocd pods

# Access services
Jenkins:   http://<EC2-IP>:8080
SonarQube: http://<EC2-IP>:9000
ArgoCD:    http://<EC2-IP>:30295
```

---

### 2. Monitoring EC2 (Manual Setup)

**Why Manual?** 
- **Learning-focused approach** - understand each component
- Deep dive into Kubernetes concepts
- Hands-on experience with Helm, ServiceMonitors, PVCs

**Step-by-Step Installation:**

#### Step 1: System Preparation
```bash
# SSH into Monitoring EC2
ssh -i key.pem ubuntu@<MONITORING-EC2-IP>

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install prerequisites
sudo apt-get install -y curl wget git vim
```

#### Step 2: Install K3s
```bash
# Install K3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Configure kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Verify installation
kubectl get nodes  # Should show: Ready
```

#### Step 3: Install Helm
```bash
# Install Helm (Kubernetes package manager)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Verify
helm repo list
```

#### Step 4: Create Namespace
```bash
kubectl create namespace monitoring
```

#### Step 5: Install Prometheus Stack

**Create custom values file:**

```bash
cat <<EOF > prometheus-values.yaml
# Prometheus configuration
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
  service:
    type: NodePort
    nodePort: 30090

# Grafana configuration
grafana:
  enabled: true
  adminPassword: "admin123"  # CHANGE AFTER FIRST LOGIN
  service:
    type: NodePort
    nodePort: 30300
  persistence:
    enabled: true
    size: 5Gi
  resources:
    requests:
      memory: "512Mi"
      cpu: "250m"
    limits:
      memory: "1Gi"
      cpu: "500m"

# AlertManager configuration
alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
  service:
    type: NodePort
    nodePort: 30903
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'cluster']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
    receivers:
    - name: 'default'

# Node Exporter (system metrics)
nodeExporter:
  enabled: true

# Kube State Metrics (Kubernetes resource metrics)
kubeStateMetrics:
  enabled: true
EOF
```

**Install the stack:**

```bash
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values prometheus-values.yaml

# Wait for pods to start (5-8 minutes)
kubectl get pods -n monitoring -w
```

**Verify installation:**

```bash
# Check all pods are Running
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring

# Check PersistentVolumeClaims
kubectl get pvc -n monitoring
```

**Access services:**

```bash
# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "Prometheus: http://$PUBLIC_IP:30090"
echo "Grafana:    http://$PUBLIC_IP:30300 (admin/admin123)"
echo "AlertManager: http://$PUBLIC_IP:30903"
```

---

## 🔄 Pipeline Flow

### Complete CI/CD Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Developer Push                                               │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Jenkins CI Pipeline                                          │
├─────────────────────────────────────────────────────────────────┤
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │  Checkout   │→ │ SonarQube   │→ │ Quality Gate│            │
│   │  (Git)      │  │ Analysis    │  │ (Block/Pass)│            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │  Trivy FS   │→ │ Docker Build│→ │ Trivy Image │            │
│   │  Scan       │  │             │  │ Scan        │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐                              │
│   │  Push to    │→ │ Update Git  │                              │
│   │  DockerHub  │  │ Manifest    │                              │
│   └─────────────┘  └─────────────┘                              │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Git Repository (Source of Truth)                            │
│   - deployment.yaml updated with new image tag                 │
│   - Commit: "Update image to sadikgok/app:BUILD_NUMBER"        │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. ArgoCD GitOps Engine                                         │
├─────────────────────────────────────────────────────────────────┤
│   - Polls Git every 3 minutes (or webhook)                      │
│   - Detects manifest change                                     │
│   - Status: "OutOfSync"                                         │
│   - Pulls new YAML from Git                                     │
│   - Applies to Kubernetes cluster                               │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Kubernetes Deployment                                        │
├─────────────────────────────────────────────────────────────────┤
│   - Terminates old pods                                         │
│   - Pulls new image from DockerHub                              │
│   - Starts new pods with updated image                          │
│   - Service routes traffic to new pods                          │
└───────────────────┬─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Monitoring & Observability                                   │
├─────────────────────────────────────────────────────────────────┤
│   - Prometheus scrapes metrics (30s interval)                   │
│   - Grafana displays dashboards                                 │
│   - AlertManager monitors health                                │
│   - Logs available via kubectl logs                             │
└─────────────────────────────────────────────────────────────────┘
```

### Jenkinsfile Stages Explained

```groovy
// Stage 1: Environment Setup
tools {
    jdk 'jdk17'          // SonarQube requires Java
    nodejs 'node22'      // Application dependencies
}

// Stage 2: Clean Workspace
stage('Workspace Cleanup') {
    // Remove old build artifacts
}

// Stage 3: Code Checkout
stage('Git Checkout') {
    git branch: 'master', url: 'https://github.com/...'
}

// Stage 4: Install Dependencies
stage('Install Dependencies') {
    sh 'npm install'      // Install Node.js packages
}

// Stage 5: SonarQube Analysis (SAST)
stage('SonarQube Analysis') {
    withSonarQubeEnv('SonarQube') {
        sh 'sonar-scanner'
    }
}

// Stage 6: Quality Gate
stage('Quality Gate') {
    timeout(time: 10, unit: 'MINUTES') {
        waitForQualityGate abortPipeline: true
    }
}

// Stage 7: Filesystem Scan
stage('Trivy FS Scan') {
    sh '''
        docker run --rm -v $WORKSPACE:/scan \
        aquasec/trivy:latest fs /scan > trivyfs.txt
    '''
}

// Stage 8: Docker Build
stage('Docker Build') {
    sh 'docker build -t sadikgok/app:${BUILD_NUMBER} .'
}

// Stage 9: Docker Push
stage('Docker Push') {
    withDockerRegistry(credentialsId: 'dockerhub') {
        sh 'docker push sadikgok/app:${BUILD_NUMBER}'
    }
}

// Stage 10: Image Scan
stage('Trivy Image Scan') {
    sh '''
        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
        aquasec/trivy:latest image sadikgok/app:${BUILD_NUMBER}
    '''
}

// Stage 11: Update Manifest (GitOps)
stage('Update Deployment') {
    withCredentials([gitUsernamePassword(credentialsId: 'github')]) {
        sh '''
            sed -i "s|image: sadikgok/app:.*|image: sadikgok/app:${BUILD_NUMBER}|" \
                kubernetes/deployment.yaml
            git add kubernetes/deployment.yaml
            git commit -m "Update image to ${BUILD_NUMBER} [skip ci]"
            git push origin master
        '''
    }
}

// Stage 12: Cleanup
stage('Docker Cleanup') {
    sh 'docker system prune -af'
}
```

---

## 🔐 Security Implementation

### Multi-Layer Security Approach

```
┌─────────────────────────────────────────┐
│  Layer 1: Static Analysis (SAST)       │
│  Tool: SonarQube                        │
│  Checks: Code quality, bugs, smells,   │
│          security hotspots              │
└──────────────┬──────────────────────────┘
               │ ✅ Pass
               ▼
┌─────────────────────────────────────────┐
│  Layer 2: Quality Gate                 │
│  Blocks: Critical issues, coverage < X │
└──────────────┬──────────────────────────┘
               │ ✅ Pass
               ▼
┌─────────────────────────────────────────┐
│  Layer 3: Filesystem Scan               │
│  Tool: Trivy                            │
│  Checks: Dependencies, source code      │
└──────────────┬──────────────────────────┘
               │ ✅ Pass
               ▼
┌─────────────────────────────────────────┐
│  Layer 4: Container Image Scan         │
│  Tool: Trivy                            │
│  Checks: OS packages, libraries, CVEs  │
└──────────────┬──────────────────────────┘
               │ ✅ Pass
               ▼
          [Deploy]
```

### ARM64 Compatibility Solution

**Problem:** Trivy binaries not available for ARM64 when project started.

**Solution:** Run Trivy as ephemeral Docker containers (DooD approach).

```groovy
// Instead of: trivy fs . (binary doesn't exist)
// We use:
docker run --rm -v $WORKSPACE:/scan aquasec/trivy:latest fs /scan

// Why this works:
// 1. Docker pulls ARM64-compatible Trivy image
// 2. Mounts workspace into container
// 3. Runs scan inside container
// 4. Container auto-deletes after scan (ephemeral)
// 5. Results stored in trivyfs.txt on host
```

---

## 📊 Monitoring & Observability

### Metrics Collection Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Monitoring EC2 (Prometheus Stack)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Prometheus (Scraper)                                 │  │
│  │  - Scrapes every 30 seconds                          │  │
│  │  - Stores 15 days of metrics                         │  │
│  │  - 10GB persistent storage                           │  │
│  └──────┬───────────────────────────────────────────────┘  │
│         │                                                   │
│         ├─────────────────────┬─────────────────┐          │
│         │                     │                 │          │
│         ▼                     ▼                 ▼          │
│  ┌────────────┐       ┌────────────┐    ┌────────────┐    │
│  │ Jenkins    │       │ Jenkins    │    │ Monitoring │    │
│  │ App        │       │ EC2        │    │ EC2        │    │
│  │ Metrics    │       │ System     │    │ System     │    │
│  │ :8080/     │       │ Metrics    │    │ Metrics    │    │
│  │ prometheus │       │ :9100      │    │ :9100      │    │
│  └────────────┘       └────────────┘    └────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### ServiceMonitor Configuration (Kubernetes-Native)

**Jenkins Application Metrics:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jenkins
  namespace: monitoring
  labels:
    app: jenkins
    release: prometheus-stack  # Critical: Must match Prometheus selector
spec:
  selector:
    matchLabels:
      app: jenkins
  endpoints:
  - port: metrics
    path: /prometheus
    interval: 30s
```

**Jenkins Node Exporter (System Metrics):**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jenkins-node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: jenkins-node-exporter
  endpoints:
  - port: metrics
    interval: 30s
```

**Why ServiceMonitor over additionalScrapeConfigs?**

| Feature | ServiceMonitor | additionalScrapeConfigs |
|---------|---------------|------------------------|
| Discovery | Automatic (label-based) | Manual configuration |
| Updates | No restart needed | Requires Prometheus restart |
| Approach | Kubernetes-native | Traditional Prometheus |
| Enterprise Use | ✅ Standard | ❌ Legacy |
| Learning Value | ✅ High | ❌ Low |

### Grafana Dashboards

| ID | Dashboard | Purpose |
|----|-----------|---------|
| **1860** | Node Exporter Full | CPU, RAM, Disk, Network for both EC2s |
| **9964** | Jenkins Performance | Job metrics, queue, executors, build times |
| **13770** | Kubernetes Cluster Monitoring | Pods, deployments, resource usage |
| **12006** | ArgoCD | Application sync status, health checks |

**Import Dashboards:**

```
Grafana UI → Dashboards → Import
Enter ID: 1860
Select Data Source: Prometheus
Click Import
```

---

## 🎓 Key Learnings

### 1. Architecture Decisions Have Trade-offs

**Decision:** Docker-outside-Docker (DooD)
- ✅ **Pro:** Lightweight, performant, ARM64 compatible
- ⚠️  **Con:** Security risk (socket access = root power)
- 📝 **Learning:** Document and accept risks in learning environments

**Decision:** Separate monitoring EC2
- ✅ **Pro:** Blast radius isolation, resource contention avoidance
- ⚠️  **Con:** Higher cost ($)
- 📝 **Learning:** Production-grade thinking, operational maturity

### 2. GitOps Requires Mental Shift

**Old Way (Imperative):**
```bash
kubectl apply -f deployment.yaml  # Direct cluster access
```

**New Way (Declarative/GitOps):**
```bash
git commit deployment.yaml         # Declare desired state
git push                           # Single source of truth
# ArgoCD handles the rest
```

**Benefits Experienced:**
- Full audit trail (who deployed what, when)
- Easy rollback (git revert)
- No cluster credentials in CI
- Sync status visible in ArgoCD UI

### 3. Kubernetes-Native Monitoring is Powerful

**Discovery:** ServiceMonitors enable dynamic target discovery.

**Example:**
```bash
# Add new Jenkins node
kubectl apply -f new-node-servicemonitor.yaml

# Prometheus automatically discovers it
# No restart, no manual config change
# Just label matching: release=prometheus-stack
```

### 4. Resource Contention is Real

**Observation:** Running Jenkins build + Prometheus scrape simultaneously caused:
- CPU spikes to 90%+
- Increased memory pressure
- Slower build times

**Solution:** Separate infrastructure prevents competition.

**Learning:** Monitor resource usage, plan capacity, isolate workloads.

---

## ⚠️ Known Limitations & Future Work

### Current Limitations

These are **documented trade-offs**, not mistakes:

**1. Docker Socket Risk**
- **Current:** `/var/run/docker.sock` mounted in Jenkins
- **Risk:** Container escape potential
- **Mitigation (Future):** Kaniko, Rootless Docker, or dedicated build nodes

**2. Single-Node Kubernetes**
- **Current:** K3s on single EC2 instance
- **Risk:** No high availability
- **Mitigation (Future):** Multi-node K3s or EKS

**3. Secrets in Plain Text**
- **Current:** Grafana password in YAML, Jenkins credentials plugin
- **Risk:** Exposure if repo public
- **Mitigation (Future):** Sealed Secrets, AWS Secrets Manager

**4. Image Tagging Strategy**
- **Current:** BUILD_NUMBER
- **Issue:** Not immutable or descriptive
- **Mitigation (Future):** Git commit SHA, semantic versioning

**5. ArgoCD Auto-Sync**
- **Current:** Automatic deployment on Git change
- **Risk:** Bugs go to production immediately
- **Mitigation (Future):** Manual approval for prod, sync waves

### Future Improvements

**Priority 1 (Next Sprint):**
- [ ] Git SHA-based image tags
- [ ] SonarQube hard-fail on critical issues
- [ ] Trivy fail pipeline on HIGH/CRITICAL CVEs
- [ ] Move Grafana password to Kubernetes Secret

**Priority 2 (Learning & CV):**
- [ ] ArgoCD ApplicationSet (multi-environment)
- [ ] Helm chart conversion
- [ ] Resource limits on all pods
- [ ] Slack alerts from AlertManager

**Priority 3 (Advanced):**
- [ ] Canary/Blue-Green deployments
- [ ] SLO/Error budget tracking
- [ ] Jenkins ephemeral agents
- [ ] Multi-cluster ArgoCD

---

## 🚀 Getting Started

### Prerequisites

```bash
# AWS Account with:
- IAM permissions for EC2, VPC, Security Groups
- SSH key pair

# Local machine:
- Terraform >= 1.0
- AWS CLI configured
- SSH client
```

### Quick Start

#### 1. Clone Repository
```bash