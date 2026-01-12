# Monitoring için özel Security Group (Mevcut SG'den bağımsız)
resource "aws_security_group" "monitoring_sg" {
  name        = "Monitoring-Lab-SG"
  description = "Monitoring tools inbound rules"
  vpc_id      = aws_default_vpc.Default.id

  # Gerekli Portlar: 22(SSH), 3000(Grafana-Default), 31000(Grafana-NodePort), 9090(Prometheus)
  ingress = [
    for port in [22, 3000, 9090, 31000] : {
      description      = "Monitoring ports"
      from_port        = port
      to_port          = port
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Monitoring-Lab-SG" }
}

# Monitoring Sunucusu (x86 - t3.medium)
resource "aws_instance" "monitoring_server" {
  ami                    = "ami-02b8269d5e85954ef" # ap-south-1 Ubuntu 24.04 x86 AMI
  instance_type          = "t3.medium"             # 2 vCPU, 4GB RAM (Monitoring için ideal)
  key_name               = "DevopsKeyPair"
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "Monitoring-Server-Lab"
  }
}

# --- MONITORING OUTPUTS ---
output "monitoring_public_ip" {
  value = aws_instance.monitoring_server.public_ip
}
