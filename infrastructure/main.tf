terraform {
  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.0" }
    tls   = { source = "hashicorp/tls", version = "~> 4.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

# ----------------------------
# VARIABLES (same file)
# ----------------------------
variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "cluster_name" {
  type    = string
  default = "DevOps-EKS-Cluster"
}

# ONLY your IPs / office/VPN
variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to access admin UIs and EKS public endpoint"
  default     = ["YOUR_PUBLIC_IP/32"]
}

variable "budget_email" {
  type    = string
  default = "sadik.gok@gmail.com"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "FinOps-DevOps"
      Environment = "Production"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  common_tags = {}
  name_prefix = var.cluster_name
}

# ----------------------------
# DATA
# ----------------------------
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
}

# ----------------------------
# SSH KEY (optional; keep for now)
# ----------------------------
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

# ----------------------------
# VPC
# ----------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name                                        = "${local.name_prefix}-VPC"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-IGW" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${local.name_prefix}-Public-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "${local.name_prefix}-Private-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name_prefix}-Public-RT" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-Private-RT-VPCE-Only" }
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

# ----------------------------
# VPC ENDPOINTS SG
# ----------------------------
resource "aws_security_group" "vpc_endpoints" {
  name        = "VPC-Endpoints-SG"
  description = "Security group for interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# S3 Gateway (route only private RT)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  # (Optional) tighten later - kept simple for now
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:ListBucket"]
      Resource  = "*"
    }]
  })

  tags = { Name = "S3-Gateway-Endpoint" }
}

# Interface endpoint helper
locals {
  interface_endpoints = toset([
    "ecr.api",
    "ecr.dkr",
    "eks",
    "sts",
    "logs",
    "autoscaling",
    "elasticloadbalancing",

    # NAT yokken operasyon için KRİTİK (SSM)
    "ssm",
    "ssmmessages",
    "ec2messages",
  ])
}

resource "aws_vpc_endpoint" "ifaces" {
  for_each            = local.interface_endpoints
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "VPCE-${each.value}" }
}

# ----------------------------
# IAM
# ----------------------------
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

resource "aws_iam_role_policy_attachment" "admin_adminaccess" {
  role       = aws_iam_role.admin_eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}



resource "aws_iam_instance_profile" "admin" {
  name = "Admin-Instance-Profile"
  role = aws_iam_role.admin_eks_role.name
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-Cluster-Role"
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

resource "aws_iam_role" "eks_nodes" {
  name = "${var.cluster_name}-Node-Role"
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
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.eks_nodes.name
  policy_arn = each.value
}

# ----------------------------
# SECURITY GROUPS (restricted)
# ----------------------------
resource "aws_security_group" "jenkins" {
  name        = "Jenkins-SG"
  description = "Jenkins, Docker, SonarQube"
  vpc_id      = aws_vpc.main.id

  # SSH (ideally remove and use SSM)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "argo" {
  name        = "ArgoCD-SG"
  description = "ArgoCD admin host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "monitoring" {
  name        = "Monitoring-SG"
  description = "Prometheus and Grafana"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-SG"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Allow all inside VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------
# EC2 (ARM64 public)
# ----------------------------
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
  tags = { Name = "Jenkins-Docker-Host" }
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
  tags = { Name = "ArgoCD-Admin-Host" }
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
  tags = { Name = "Monitoring-Server" }
}

# ----------------------------
# EKS (dual endpoint; public restricted)
# ----------------------------
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)

    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.allowed_cidrs

    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.ifaces,
  ]

  tags = { Name = var.cluster_name }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "arm64-private-workers"
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

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_node_policies,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.ifaces,
  ]

  tags = { Name = var.cluster_name }
}

# -------------------------------------------------------------------
# EKS ACCESS CONTROL (Cluster Admin for Admin EC2 Role)
# -------------------------------------------------------------------

resource "aws_eks_access_entry" "admin_role" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.admin_eks_role.arn
  type          = "STANDARD"

  depends_on = [aws_eks_cluster.main]
}

resource "aws_eks_access_policy_association" "admin_role_cluster_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.admin_eks_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin_role]
}

# ----------------------------
# ECR
# ----------------------------
resource "aws_ecr_repository" "app" {
  name                 = "finops-app-repo"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

# ----------------------------
# BUDGET
# ----------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "devops-monthly-budget"
  budget_type  = "COST"
  limit_amount = "60"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}

# ----------------------------
# OUTPUTS (short)
# ----------------------------
output "jenkins_url" { value = "http://${aws_instance.jenkins.public_ip}:8080" }
output "sonarqube_url" { value = "http://${aws_instance.jenkins.public_ip}:9000" }
output "argocd_url" { value = "http://${aws_instance.argo.public_ip}" }
output "grafana_url" { value = "http://${aws_instance.monitoring.public_ip}:3000" }
output "prometheus_url" { value = "http://${aws_instance.monitoring.public_ip}:9090" }
output "ecr_repository" { value = aws_ecr_repository.app.repository_url }
output "eks_cluster_name" { value = aws_eks_cluster.main.name }
output "ssh_key_file" { value = local_file.devops_key_file.filename }
