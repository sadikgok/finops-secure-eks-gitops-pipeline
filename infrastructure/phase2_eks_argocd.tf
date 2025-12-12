# ----------------------------
# EC2 (Argo - ARM64 public)
# ----------------------------
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

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ----------------------------
# OUTPUTS
# ----------------------------

output "argocd_url" {
  value = "http://${aws_instance.argo.public_ip}"
}