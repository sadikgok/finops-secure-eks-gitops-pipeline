#!/bin/bash
# ----------------------------------
# 0. Genel Güncelleme ve Kullanıcı Tanımı
# ----------------------------------
sudo apt update
sudo apt upgrade -y

# Mevcut kullanıcıyı otomatik olarak almak  için
# (EC2 user_data içinde çalıştığında root olmayabilir)
CURRENT_USER=$(whoami) 

# ----------------------------------
# 1. Java 17 Kurulumu (Jenkins için)
# ----------------------------------
wget -O - https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo tee /etc/apt/keyrings/adoptium.asc
echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | sudo tee /etc/apt/sources.list.d/adoptium.list
sudo apt update -y
sudo apt install temurin-17-jdk -y

# ----------------------------------
# 2. Jenkins Kurulumu
# ----------------------------------
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update -y
sudo apt-get install jenkins -y
sudo systemctl enable jenkins
sudo systemctl start jenkins

# ----------------------------------
# 3. Docker Kurulumu
# ----------------------------------
sudo apt-get install docker.io -y
# Jenkins ve Mevcut Kullanıcıyı docker grubuna ekle
sudo usermod -aG docker "$${CURRENT_USER}"
sudo usermod -aG docker jenkins
sudo systemctl enable docker
sudo systemctl start docker

# ----------------------------------
# 4. SonarQube Container Kurulumu
# ----------------------------------
# --restart always ile SonarQube'u 9000 portunda başlat
# Not: Docker grubuna ekleme yapıldığı için bu komut hala çalışmayabilir 
#      yeniden başlatmadan önce. Ancak bu bir EC2 user_data kısıtlamasıdır.
sudo docker run -d --restart always --name sonar -p 9000:9000 sonarqube:lts-community

# ----------------------------------
# 5. Trivy Kurulumu (Güvenlik Tarama Aracı)
# ----------------------------------
sudo apt-get install wget apt-transport-https gnupg lsb-release -y
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy -y

# ----------------------------------
# 6. AWS CLI v2 Kurulumu
# ----------------------------------
sudo apt install curl unzip -y
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
# Kurulum dosyalarını temizle
rm awscliv2.zip
rm -rf aws/

# ----------------------------------
# 6.5. AWS CLI Konfigürasyonu (IAM Rolü Kullanımı)
# ----------------------------------
# Fonksiyon: AWS CLI config dosyasını belirli bir kullanıcı için kurar
configure_aws_cli() {
    local USERNAME=$1
    local USER_HOME="/home/$${USERNAME}"
    
    # Özel bir home dizini olmayan servis kullanıcıları için kontrol
    if [ "$USERNAME" == "jenkins" ] && [ ! -d "$USER_HOME" ]; then
        USER_HOME="/var/lib/jenkins"
    fi

    # .aws klasörünü oluştur
    mkdir -p "$${USER_HOME}/.aws"

    # Yapılandırma dosyasını yaz
    cat <<EOF > "$${USER_HOME}/.aws/config"
[default]
region = eu-north-1
output = json
EOF

    # Kullanıcının home dizinine ve .aws klasörüne izinleri ayarla
    chown -R "$${USERNAME}":"$${USERNAME}" "$${USER_HOME}/.aws"
    echo "AWS CLI $${USERNAME} kullanıcısı için yapılandırıldı: $${USER_HOME}/.aws"
}

# 1. İlk olarak, oturum açmış kullanıcıyı yapılandır
configure_aws_cli "$${CURRENT_USER}"

# 2. İkinci olarak, Jenkins hizmet kullanıcısını yapılandır
configure_aws_cli "jenkins"
# ----------------------------------

# ----------------------------------
# 7. Kubernetes CLI Araçları (kubectl, eksctl, helm)
# ----------------------------------

# 7.1. kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl # İndirilen dosyayı temizle

# 7.2. eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# 7.3. Helm Kurulumu
echo "Helm (Kubernetes Paket Yöneticisi) Kuruluyor..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y

# ----------------------------------
# 8. Yeniden Başlatma (Güvenilirlik İçin)
# ----------------------------------
echo "Kurulum tamamlandı. Docker grubunun uygulanması ve servislerin kararlılığı için sunucu yeniden başlatılıyor..."
sudo reboot