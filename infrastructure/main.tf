# main.tf

# -----------------------------------------------------------------------------
# 0. PROVIDER, VARIABLES ve TEMEL TANIMLAR
# -----------------------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

locals {
  cluster_name             = "DevOps-EKS-Cluster"
  jenkins_instance_type    = "t4g.large"     # ARM64 (Graviton)
  argo_instance_type       = "t4g.large"     # ARM64 (Graviton)
  monitoring_instance_type = "t4g.large"     # ARM64 (Graviton) - FinOps odaklı
  eks_worker_type          = "t4g.medium"    # ARM64 (Graviton)
  vpc_cidr                 = "10.0.0.0/16"
}

# Bölgedeki kullanılabilir AZ'leri dinamik olarak alır
data "aws_availability_zones" "available" {
  state = "available"
}

# Amazon Linux 2023 Graviton (ARM64) AMI'yi dinamik olarak çeker
data "aws_ami" "amazon_linux_2023_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
}

# -----------------------------------------------------------------------------
# 1. SSH Key Pair Oluşturma ve Kaydetme
# -----------------------------------------------------------------------------

resource "tls_private_key" "devops_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "devops_keypair" {
  key_name   = "devops-auto-key"
  public_key = tls_private_key.devops_key.public_key_openssh
}

resource "local_file" "devops_key_file" {
  content         = tls_private_key.devops_key.private_key_pem
  filename        = "devops-auto-key.pem"
  file_permission = "0400"
}

# -----------------------------------------------------------------------------
# 2. VPC, IGW ve Subnet Tanımları (HEPSİ BU VPC İÇİNDE)
# -----------------------------------------------------------------------------

resource "aws_vpc" "project_vpc" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name                                          = "${local.cluster_name}-VPC"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.project_vpc.id
  tags   = { Name = "${local.cluster_name}-IGW" }
}

# 2.1. Public Subnet'ler (Jenkins, Argo, Monitoring, NAT GW, ELB'ler için)
resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.project_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name                                          = "${local.cluster_name}-Public-Subnet-AZ1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.project_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = {
    Name                                          = "${local.cluster_name}-Public-Subnet-AZ2"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                      = "1"
  }
}

# 2.2. NAT Gateway ve Private Subnet'ler (EKS Worker Node'ları için)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags   = { Name = "${local.cluster_name}-NAT-EIP" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_az1.id
  tags          = { Name = "${local.cluster_name}-NAT-GW" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_subnet" "private_az1" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
    Name                                          = "${local.cluster_name}-Private-Subnet-AZ1"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "private_az2" {
  vpc_id            = aws_vpc.project_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
    Name                                          = "${local.cluster_name}-Private-Subnet-AZ2"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

# 2.3. Route Table'lar ve İlişkilendirmeler
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.project_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.cluster_name}-Public-RT" }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.project_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags       = { Name = "${local.cluster_name}-Private-RT" }
  depends_on = [aws_nat_gateway.nat]
}

resource "aws_route_table_association" "public_assoc_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_assoc_az1" {
  subnet_id      = aws_subnet.private_az1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_assoc_az2" {
  subnet_id      = aws_subnet.private_az2.id
  route_table_id = aws_route_table.private_rt.id
}

# -----------------------------------------------------------------------------
# 3. IAM Rolleri (EC2'ler ve EKS İçin)
# -----------------------------------------------------------------------------

# 3.1. Jenkins/Argo/Monitoring EC2 IAM Rolü (EKS'i Yönetmek İçin)
resource "aws_iam_role" "admin_eks_role" {
  name = "Admin-EKS-Manager-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
    }],
  })
}

resource "aws_iam_role_policy_attachment" "admin_eks_attach" {
  role       = aws_iam_role.admin_eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# YENİ: ECR erişimi için (Jenkins'in Docker image push edebilmesi için)
resource "aws_iam_role_policy_attachment" "admin_ecr_attach" {
  role       = aws_iam_role.admin_eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "admin_instance_profile" {
  name = "Admin-Instance-Profile"
  role = aws_iam_role.admin_eks_role.name
}

# 3.2. EKS Control Plane Rolü
resource "aws_iam_role" "eks_master_role" {
  name = "${local.cluster_name}-Control-Plane-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      },
    }],
  })
}

resource "aws_iam_role_policy_attachment" "eks_master_policy" {
  role       = aws_iam_role.eks_master_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 3.3. EKS Worker Node Rolü (EC2)
resource "aws_iam_role" "eks_node_role" {
  name = "${local.cluster_name}-Worker-Node-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
    }],
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy_1" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_policy_2" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_policy_3" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -----------------------------------------------------------------------------
# 4. GÜVENLİK GRUPLARI (Tümü aws_vpc.project_vpc içine bağlı)
# -----------------------------------------------------------------------------

# 4.1. Jenkins Host SG
resource "aws_security_group" "jenkins_sg" {
  name        = "Jenkins-Host-SG"
  description = "Security group for Jenkins, Docker, and SonarQube"
  vpc_id      = aws_vpc.project_vpc.id

  # SSH, Jenkins, SonarQube portları
  ingress = [
    for port in [22, 8080, 9000] : {
      description      = "Inbound rule for Port ${port}"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      security_groups  = []
      self             = false
      prefix_list_ids  = []
    }
  ]

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Jenkins-Host-SG" }
}

# 4.2. Argo Admin Host SG
resource "aws_security_group" "argo_admin_sg" {
  name        = "ArgoCD-Kube-Admin-SG"
  description = "Security group for ArgoCD and Kubernetes Admin"
  vpc_id      = aws_vpc.project_vpc.id

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ArgoCD UI"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ArgoCD UI HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ArgoCD-Kube-Admin-SG" }
}

# 4.3. Prometheus/Grafana Monitoring SG
resource "aws_security_group" "monitoring_sg" {
  name        = "My-Monitoring-Server-SG"
  description = "Security group for Prometheus and Grafana monitoring"
  vpc_id      = aws_vpc.project_vpc.id

  # SSH, Prometheus, Grafana portları
  ingress = [
    for port in [22, 9090, 3000] : {
      description      = "Inbound rule for Port ${port}"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      security_groups  = []
      self             = false
      prefix_list_ids  = []
    }
  ]

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "My-Monitoring-Server-SG" }
}

# -----------------------------------------------------------------------------
# 5. EC2 INSTANCE'LAR (Tümü ARM64 - Graviton)
# -----------------------------------------------------------------------------

# 5.1. Jenkins/Docker Host (t4g.large - ARM64)
resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = local.jenkins_instance_type
  key_name               = aws_key_pair.devops_keypair.key_name
  subnet_id              = aws_subnet.public_az1.id
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.admin_instance_profile.name
  user_data              = file("./03_install.sh")
  
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { 
    Name = "Jenkins-Docker-Host"
    Type = "CI-CD-Server"
  }
}

# 5.2. ArgoCD/Kube Admin Host (t4g.large - ARM64)
resource "aws_instance" "argo_admin_master" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = local.argo_instance_type
  key_name               = aws_key_pair.devops_keypair.key_name
  subnet_id              = aws_subnet.public_az2.id
  vpc_security_group_ids = [aws_security_group.argo_admin_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.admin_instance_profile.name
  user_data              = file("./04_argo_install.sh")
  
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { 
    Name = "ArgoCD-Kube-Admin-Host"
    Type = "GitOps-Server"
  }
}

# 5.3. Prometheus/Grafana Monitoring Host (t4g.large - ARM64)
resource "aws_instance" "monitoring_server" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = local.monitoring_instance_type
  key_name               = aws_key_pair.devops_keypair.key_name
  subnet_id              = aws_subnet.public_az1.id
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.admin_instance_profile.name
  user_data              = file("./05_monitoring_install.sh")
  
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { 
    Name = "My-Monitoring-Server"
    Type = "Monitoring-Server"
  }
}

# -----------------------------------------------------------------------------
# 6. EKS KÜMESİ VE NODE GRUPLARI
# -----------------------------------------------------------------------------

# 6.1. EKS Kümesi (Control Plane)
resource "aws_eks_cluster" "eks_cluster" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_master_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.public_az1.id,
      aws_subnet.public_az2.id,
      aws_subnet.private_az1.id,
      aws_subnet.private_az2.id,
    ]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [aws_iam_role_policy_attachment.eks_master_policy]

  tags = {
    Name = local.cluster_name
  }
}

# 6.2. EKS Node Group (Worker Düğümleri) - t4g.medium ARM64
resource "aws_eks_node_group" "eks_worker_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "finops-t4g-medium-workers"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.private_az1.id, aws_subnet.private_az2.id]
  
  # ARM64 için özel ayarlar
  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = [local.eks_worker_type]
  disk_size      = 20

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "worker"
    arch = "arm64"
  }

  tags = {
    Name = "EKS-Worker-Node-${local.eks_worker_type}"
    Type = "EKS-Worker"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy_1,
    aws_iam_role_policy_attachment.eks_node_policy_2,
    aws_iam_role_policy_attachment.eks_node_policy_3,
  ]
}

# -----------------------------------------------------------------------------
# 7. YENİ: ECR Repository (Docker Image Registry)
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app_repo" {
  name                 = "finops-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "FinOps-App-ECR-Repository"
    Environment = "Production"
  }
}

resource "aws_ecr_lifecycle_policy" "app_repo_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["1.0"]
        countType     = "imageCountMoreThan"
        countNumber   = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# -----------------------------------------------------------------------------
# 8. EK ALTYAPI (Budget)
# -----------------------------------------------------------------------------

# 8.1. Bütçe Tanımı (FinOps)
resource "aws_budgets_budget" "monthly_budget" {
  name              = "monthly-devops-budget"
  budget_type       = "COST"
  limit_amount      = "100"
  limit_unit        = "USD"
  time_period_start = "2025-01-01T00:00:00Z"  # ✅ ISO 8601 formatı
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 70
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["sadik.gok@gmail.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["sadik.gok@gmail.com"]
  }

  tags = {
    Name = "DevOps-Monthly-Budget"
  }
}

# -----------------------------------------------------------------------------
# 9. ÇIKTILAR (OUTPUTS)
# -----------------------------------------------------------------------------

output "jenkins_host_ip" {
  description = "Jenkins/Docker Host Public IP"
  value       = aws_instance.jenkins_master.public_ip
}

output "jenkins_url" {
  description = "Jenkins Web Interface"
  value       = "http://${aws_instance.jenkins_master.public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube Web Interface"
  value       = "http://${aws_instance.jenkins_master.public_ip}:9000"
}

output "argo_admin_host_ip" {
  description = "ArgoCD Kube Admin Host Public IP"
  value       = aws_instance.argo_admin_master.public_ip
}

output "argo_url" {
  description = "ArgoCD Web Interface (after installation)"
  value       = "http://${aws_instance.argo_admin_master.public_ip}"
}

output "monitoring_server_ip" {
  description = "Prometheus/Grafana Monitoring Server Public IP"
  value       = aws_instance.monitoring_server.public_ip
}

output "prometheus_url" {
  description = "Prometheus Web Interface"
  value       = "http://${aws_instance.monitoring_server.public_ip}:9090"
}

output "grafana_url" {
  description = "Grafana Web Interface"
  value       = "http://${aws_instance.monitoring_server.public_ip}:3000"
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.eks_cluster.name
}

output "ecr_repository_url" {
  description = "ECR Repository URL for Docker Images"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ssh_key_path" {
  description = "SSH private key file path"
  value       = local_file.devops_key_file.filename
}

output "aws_region" {
  description = "AWS Region"
  value       = "ap-south-1"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.project_vpc.id
}

output "setup_instructions" {
  description = "Quick Setup Instructions"
  value = <<-EOT
    
    ╔════════════════════════════════════════════════════════════════╗
    ║          🚀 DevOps Infrastructure Successfully Created!        ║
    ╚════════════════════════════════════════════════════════════════╝
    
    📦 SERVICES:
    ├─ Jenkins:    http://${aws_instance.jenkins_master.public_ip}:8080
    ├─ SonarQube:  http://${aws_instance.jenkins_master.public_ip}:9000
    ├─ ArgoCD:     http://${aws_instance.argo_admin_master.public_ip}
    ├─ Prometheus: http://${aws_instance.monitoring_server.public_ip}:9090
    └─ Grafana:    http://${aws_instance.monitoring_server.public_ip}:3000
    
    🔐 SSH ACCESS:
    ssh -i ${local_file.devops_key_file.filename} ec2-user@${aws_instance.jenkins_master.public_ip}
    
    🔑 JENKINS INITIAL PASSWORD:
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
    
    📦 ECR REPOSITORY:
    ${aws_ecr_repository.app_repo.repository_url}
    
    ☸️  EKS CLUSTER:
    aws eks update-kubeconfig --name ${aws_eks_cluster.eks_cluster.name} --region ap-south-1
    
    💰 ARCHITECTURE: ARM64 (Graviton) - FinOps Optimized
    💵 ESTIMATED MONTHLY COST: ~$100-150
    
  EOT
}