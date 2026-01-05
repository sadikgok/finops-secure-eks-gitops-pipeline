terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_security_group" "devops_sg" {
  name        = "My-Jenkins-Server-SG"
  description = "DevOps Lab inbound rules"

  ingress = [
    for port in [22, 80, 443, 8080, 9000] : {
      description      = "inbound rules"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "My-Jenkins-Server-SG"
  }
}

resource "aws_instance" "devops" {
  ami                    = "ami-027308df79a86d22c"
  instance_type          = "t4g.large"
  key_name               = "DevopsKeyPair"
  vpc_security_group_ids = [aws_security_group.devops_sg.id]

  # install.sh dosyası bu .tf dosyasıyla aynı klasörde olmalı
  user_data = file("${path.module}/install.sh")

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "My-Jenkins-Server"
  }
}

# --- OUTPUTS ---

output "public_ip" {
  value       = aws_instance.devops.public_ip
  description = "Public IP of the DevOps EC2"
}

output "ssh" {
  value       = "ssh -i <your_key.pem> ubuntu@${aws_instance.devops.public_ip}"
  description = "SSH command"
}

output "jenkins_url" {
  value       = "http://${aws_instance.devops.public_ip}:8080"
  description = "Jenkins UI"
}

output "sonarqube_url" {
  value       = "http://${aws_instance.devops.public_ip}:9000"
  description = "SonarQube UI"
}