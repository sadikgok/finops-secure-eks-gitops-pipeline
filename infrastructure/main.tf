# main.tf - ARM64 DevOps Infrastructure (NAT-less)

terraform {
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "aws" {
  region = "ap-south-1"
}

locals {
  cluster_name = "DevOps-EKS-Cluster"
  common_tags = {
    Project     = "FinOps-DevOps"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name  = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
}

# -----------------------------------------------------------------------------
# SSH KEY PAIR
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
# VPC & NETWORKING
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.common_tags, {
    Name                                    = "${local.cluster_name}-VPC"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.cluster_name}-IGW" })
}

# Public Subnets (Internet erişimi olan alt ağlar)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name                                    = "${local.cluster_name}-Public-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                  = "1"
  })
}

# Private Subnets (Internet erişimi OLMAYAN alt ağlar)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(local.common_tags, {
    Name                                    = "${local.cluster_name}-Private-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"         = "1"
  })
}

# EIP ve NAT Gateway KAYNAKLARI BURADAN KALDIRILDI!

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.cluster_name}-Public-RT" })
}

# Özel alt ağ rota tablosu güncellendi (0.0.0.0/0 rotası kaldırıldı)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  # NAT Gateway silindiği için buraya herhangi bir rota eklenmiyor.
  # Private Subnet'ler VPC dışına çıkamaz.
  tags = merge(local.common_tags, { Name = "${local.cluster_name}-Private-RT" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# IAM ROLES
# -----------------------------------------------------------------------------
# EC2 Admin Role (Jenkins, ArgoCD, Monitoring)
resource "aws_iam_role" "admin_eks_role" {
  name = "Admin-EKS-Manager-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "admin_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  ])
  role       = aws_iam_role.admin_eks_role.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "admin" {
  name = "Admin-Instance-Profile"
  role = aws_iam_role.admin_eks_role.name
}

# EKS Control Plane Role
resource "aws_iam_role" "eks_cluster" {
  name = "${local.cluster_name}-Cluster-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Worker Node Role
resource "aws_iam_role" "eks_nodes" {
  name = "${local.cluster_name}-Node-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])
  role       = aws_iam_role.eks_nodes.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# SECURITY GROUPS
# -----------------------------------------------------------------------------
resource "aws_security_group" "jenkins" {
  name        = "Jenkins-SG"
  description = "Jenkins, Docker, SonarQube"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [22, 8080, 9000]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "Jenkins-SG" })
}

resource "aws_security_group" "argo" {
  name        = "ArgoCD-SG"
  description = "ArgoCD and Kubernetes Admin"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [22, 80, 443]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "ArgoCD-SG" })
}

resource "aws_security_group" "monitoring" {
  name        = "Monitoring-SG"
  description = "Prometheus and Grafana"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [22, 3000, 9090]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "Monitoring-SG" })
}

# -----------------------------------------------------------------------------
# EC2 INSTANCES (ARM64)
# -----------------------------------------------------------------------------
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = "t4g.large"
  key_name               = aws_key_pair.devops_keypair.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  user_data              = file("./03_install.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, { Name = "Jenkins-Docker-Host" })
}

resource "aws_instance" "argo" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = "t4g.large"
  key_name               = aws_key_pair.devops_keypair.key_name
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.argo.id]
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  user_data              = file("./04_argo_install.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, { Name = "ArgoCD-Admin-Host" })
}

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.amazon_linux_2023_arm.id
  instance_type          = "t4g.large"
  key_name               = aws_key_pair.devops_keypair.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.admin.name
  user_data              = file("./05_monitoring_install.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, { Name = "Monitoring-Server" })
}

# -----------------------------------------------------------------------------
# EKS CLUSTER
# -----------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
  tags       = merge(local.common_tags, { Name = local.cluster_name })
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "arm64-workers"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = ["t4g.medium"]
  disk_size      = 20

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.common_tags, { Name = "EKS-ARM64-Workers" })
}

# -----------------------------------------------------------------------------
# ECR REPOSITORY
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = "finops-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
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
      action = { type = "expire" }
    }]
  })
}

# -----------------------------------------------------------------------------
# BUDGET
# -----------------------------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name              = "devops-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "50"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator      = "GREATER_THAN"
    threshold                = 80
    threshold_type           = "PERCENTAGE"
    notification_type        = "FORECASTED"
    subscriber_email_addresses = ["sadik.gok@gmail.com"]
  }
}

# -----------------------------------------------------------------------------
# OUTPUTS
# -----------------------------------------------------------------------------
output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "sonarqube_url" {
  value = "http://${aws_instance.jenkins.public_ip}:9000"
}

output "argocd_url" {
  value = "http://${aws_instance.argo.public_ip}"
}

output "grafana_url" {
  value = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "prometheus_url" {
  value = "http://${aws_instance.monitoring.public_ip}:9090"
}

output "ecr_repository" {
  value = aws_ecr_repository.app.repository_url
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "ssh_key" {
  value = local_file.devops_key_file.filename
}

output "quick_start" {
  value = <<-EOT
    
    🚀 DevOps Infrastructure Ready!
    
    Jenkins:    ${aws_instance.jenkins.public_ip}:8080
    SonarQube:  ${aws_instance.jenkins.public_ip}:9000
    ArgoCD:     ${aws_instance.argo.public_ip}
    Grafana:    ${aws_instance.monitoring.public_ip}:3000
    Prometheus: ${aws_instance.monitoring.public_ip}:9090
    
    SSH: ssh -i ${local_file.devops_key_file.filename} ec2-user@${aws_instance.jenkins.public_ip}
    
    Jenkins Password: sudo cat /var/lib/jenkins/secrets/initialAdminPassword
    ECR: ${aws_ecr_repository.app.repository_url}
    EKS: aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ap-south-1
    
    ⚠️ ÖNEMLİ: EKS işçi düğümleri (Private Subnets) internete çıkışa sahip DEĞİLDİR.
    
  EOT
}