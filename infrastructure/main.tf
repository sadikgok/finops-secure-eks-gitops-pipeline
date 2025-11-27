# ÖNCEKİ KODUNUZ AYNI KALACAK, SADECE ŞU BÖLÜMLERDE DEĞİŞİKLİK:

# -----------------------------------------------------------------------------
# 3. IAM Rolleri - ECR Yetkisi EKLENDİ
# -----------------------------------------------------------------------------
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

# YENİ: ECR erişimi için
resource "aws_iam_role_policy_attachment" "admin_ecr_attach" {
  role       = aws_iam_role.admin_eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "admin_instance_profile" {
  name = "Admin-Instance-Profile"
  role = aws_iam_role.admin_eks_role.name
}

# -----------------------------------------------------------------------------
# 7. EK ALTYAPI - BUDGET DÜZELTİLDİ
# -----------------------------------------------------------------------------

resource "aws_budgets_budget" "budget-ec2" {
  name              = "my-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "50"
  limit_unit        = "USD"
  time_period_start = "2026-01-01T00:00:00Z"  # ✅ DÜZELTİLDİ: ISO 8601 format
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 70
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["sadik.gok@gmail.com"]
  }
}

# Monitoring EIP (isteğe bağlı - yorumdan çıkarabilirsiniz)
# resource "aws_eip" "monitoring_eip" {
#   domain = "vpc"
#   tags   = { Name = "Monitoring-EIP" }
# }

# resource "aws_eip_association" "monitoring_eip_assoc" {
#   instance_id   = aws_instance.monitoring_server.id
#   allocation_id = aws_eip.monitoring_eip.id
# }

# -----------------------------------------------------------------------------
# YENİ: ECR Repository (Jenkins için)
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app_repo" {
  name                 = "myapp-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "MyApp-ECR-Repository"
  }
}

# -----------------------------------------------------------------------------
# 8. ÇIKTILAR
# -----------------------------------------------------------------------------

output "jenkins_host_ip" {
  description = "Jenkins/Docker Host Public IP"
  value       = aws_instance.jenkins_master.public_ip
}

output "argo_admin_host_ip" {
  description = "ArgoCD Kube Admin Host Public IP"
  value       = aws_instance.argo_admin_master.public_ip
}

output "monitoring_server_ip" {
  description = "Prometheus/Grafana Monitoring Server Public IP"
  value       = aws_instance.monitoring_server.public_ip
}

output "ssh_key_path" {
  description = "SSH private key file path"
  value       = local_file.devops_key_file.filename
}

output "jenkins_url" {
  description = "Jenkins Web UI"
  value       = "http://${aws_instance.jenkins_master.public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube Web UI"
  value       = "http://${aws_instance.jenkins_master.public_ip}:9000"
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = aws_ecr_repository.app_repo.repository_url
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "initial_setup_commands" {
  description = "İlk kurulum komutları"
  value = <<-EOT
    
    📦 Kurulum Tamamlandı!
    
    1️⃣  SSH ile bağlanın:
       ssh -i ${local_file.devops_key_file.filename} ec2-user@${aws_instance.jenkins_master.public_ip}
    
    2️⃣  Jenkins şifresini alın:
       docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
    
    3️⃣  Web arayüzlerine erişin:
       Jenkins:   http://${aws_instance.jenkins_master.public_ip}:8080
       SonarQube: http://${aws_instance.jenkins_master.public_ip}:9000
       ArgoCD:    http://${aws_instance.argo_admin_master.public_ip}:80
    
    4️⃣  ECR Repository:
       ${aws_ecr_repository.app_repo.repository_url}
    
  EOT
}