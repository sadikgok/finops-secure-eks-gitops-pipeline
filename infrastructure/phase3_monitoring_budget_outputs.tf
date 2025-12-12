# ----------------------------
# EC2 (Monitoring - ARM64 public)
# ----------------------------
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
# OUTPUTS
# ----------------------------
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
output "ssh_key_file" {
  value = local_file.devops_key_file.filename
}
