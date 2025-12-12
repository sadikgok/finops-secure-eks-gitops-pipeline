pipeline {
    agent any

    tools {
        jdk 'Java17'
        nodejs 'node22'
        'hudson.plugins.sonar.SonarRunnerInstallation' 'sonar-scanner'
    }

    environment {
        APP_NAME = "finops-secure-eks-gitops-pipeline"
        RELEASE = "1.0"
        DOCKER_USER = "sadikgok"
        DOCKER_ID_LOGIN = 'DockerHubTokenForJenkins'
        IMAGE_NAME = "${DOCKER_USER}/${APP_NAME}"
        IMAGE_TAG = "${RELEASE}.${BUILD_NUMBER}"
        
        // AWS/ECR
        AWS_REGION = "ap-south-1"
        AWS_ACCOUNT_ID = credentials('AWS_ACCOUNT_ID')
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPO_NAME = "finops-app-repo"
        
        // Credentials
        //JENKINS_API_TOKEN = credentials('JENKINS_API_TOKEN')
        SONAR_CREDENTIALS = 'SonarTokenForJenkins'
        
        // Trivy Reports
        TRIVY_FS_REPORT = "trivy-fs-scan.txt"
        TRIVY_JSON_REPORT = "trivy-report-${IMAGE_TAG}.json"
        TRIVY_HTML_REPORT = "trivy-report-${IMAGE_TAG}.html"
        
        // Docker Hub Cleanup
        KEEP_COUNT = 3
    }

    stages {

        stage('Cleanup Workspace') {
            steps {
                cleanWs()
                echo '🧹 Workspace temizlendi'
            }
        }

        stage('Checkout from SCM') {
            steps {
                git branch: 'main', 
                    url: 'https://github.com/sadikgok/finops-secure-eks-gitops-pipeline'
                echo '✅ Kod deposu klonlandı'
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    echo '📦 Bağımlılıklar yükleniyor...'
                    sh 'npm install'
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                script {
                    echo '🧪 Testler çalıştırılıyor...'
                    sh 'npm test || true'
                }
            }
        }

        /*stage('SonarScanner Diagnostics') {
            steps {
                script {
                    echo '🔍 SonarScanner kurulum yolu kontrol ediliyor...'
                    // SonarScanner'ın Path'te olup olmadığını kontrol edin
                    sh 'which sonar-scanner || echo "sonar-scanner Path\'te bulunamadı."'
                    
                    // Jenkins'in HOME dizinini kontrol edin (Araçlar genellikle buraya kurulur)
                    sh 'ls -l ${JENKINS_HOME}/tools/hudson.plugins.sonar.SonarRunnerInstallation/ || echo "Araçlar dizini boş veya bulunamadı."'
                    
                    // İşin çalıştığı Agent'taki tüm PATH değişkenini görüntüleyin
                    sh 'echo $PATH' 
                }
            }
        }*/

        stage("SonarQube Analysis") {
            steps {
                script {
                    echo '📊 SonarQube kod analizi başlatılıyor...'
                    withSonarQubeEnv(credentialsId: env.SONAR_CREDENTIALS) {
                        // SonarQube Scanner for JavaScript/Node.js
                         sh """
                         # Buraya PATH'i manuel olarak genişletiyoruz:
                        SONAR_SCANNER_DIR='/var/lib/jenkins/tools/hudson.plugins.sonar.SonarRunnerInstallation/sonar-scanner/bin'
                        export PATH=\$PATH:\$SONAR_SCANNER_DIR
                        
                        echo "Güncel PATH: \$PATH"
                            sonar-scanner \
                                -Dsonar.projectKey=${APP_NAME} \
                                -Dsonar.projectName=${APP_NAME} \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=node_modules/**,test/**,coverage/**
                        """
                    }
                }
            }
        }

        stage("Quality Gate") {
            steps {
                script {
                    echo '🚦 Quality Gate kontrol ediliyor...'
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: false, 
                                           credentialsId: env.SONAR_CREDENTIALS
                    }
                }
            }
        }

        stage('Trivy File System Scan') {
            steps {
                script {
                    echo '🔍 Trivy dosya sistemi taraması başlatılıyor...'
                    // Native Jenkins'te docker komutları direkt çalışır
                    sh """
                        docker run --rm \
                            -v \${WORKSPACE}:/scan \
                            aquasec/trivy:latest fs \
                            --severity HIGH,CRITICAL \
                            --format table \
                            /scan > ${TRIVY_FS_REPORT} || true
                    """
                    echo '✅ Trivy FS taraması tamamlandı'
                }
            }
        }
        
        stage('Docker Build & Tag') {
            steps {
                script {
                    echo '🔨 Docker image build ediliyor...'
                    // Native Jenkins'te docker komutları direkt çalışır
                    /*sh """
                        docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                    """*/
                    
                    // ECR_ACCOUNT_ID'yi güvenli bir şekilde çekiyoruz
                    withCredentials([
                        // Bu, 'AWS_ACCOUNT_ID' isimli Jenkins credential'ını çeker 
                        // ve değerini 'AWS_ACCOUNT_ID_SECRET' adlı bir Groovy değişkenine atar.
                        string(credentialsId: 'AWS_ACCOUNT_ID', variable: 'AWS_ACCOUNT_ID_SECRET')
                    ]) {
                        // ECR_REGISTRY'yi burada, yani Groovy'nin izin verdiği kapsamda tanımlıyoruz.
                        def ECR_REGISTRY = "${AWS_ACCOUNT_ID_SECRET}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                        
                        echo "🐳 Docker imajı oluşturuluyor ve ${ECR_REGISTRY}/${env.ECR_REPO_NAME}:${env.BUILD_NUMBER} olarak etiketleniyor..."
                        
                        // Artık ECR_REGISTRY'yi kullanabilirsiniz
                        sh "docker build -t ${ECR_REGISTRY}/${env.ECR_REPO_NAME}:${env.BUILD_NUMBER} ."
                        sh "docker tag ${ECR_REGISTRY}/${env.ECR_REPO_NAME}:${env.BUILD_NUMBER} ${ECR_REGISTRY}/${env.ECR_REPO_NAME}:latest"
                        echo '✅ Docker image oluşturuldu ve tag\'lendi'
                    }
                }
            }
        }

        stage("Trivy Image Scan") {
            steps {
                script {
                    echo '🔍 Trivy image güvenlik taraması başlatılıyor...'
                    
                    // JSON rapor oluştur
                    sh """
                        docker run --rm \
                            -v /var/run/docker.sock:/var/run/docker.sock \
                            -v \${WORKSPACE}:/report \
                            aquasec/trivy:latest image \
                            --format json \
                            --severity HIGH,CRITICAL \
                            --output /report/${TRIVY_JSON_REPORT} \
                            ${IMAGE_NAME}:${IMAGE_TAG} || true
                    """

                    // HTML rapor oluştur
                    sh """
                        docker run --rm \
                            -v \${WORKSPACE}:/report \
                            aquasec/trivy:latest convert \
                            --format template \
                            --template "@contrib/html.tpl" \
                            --output /report/${TRIVY_HTML_REPORT} \
                            /report/${TRIVY_JSON_REPORT} || true
                    """
                    
                    echo '✅ Trivy güvenlik raporları oluşturuldu'
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                script {
                    echo '📤 Docker Hub\'a image push ediliyor...'
                    withCredentials([usernamePassword(
                        credentialsId: DOCKER_ID_LOGIN,
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )]) {
                        sh """
                            echo \$DOCKER_PASSWORD | docker login -u \$DOCKER_USERNAME --password-stdin
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest
                        """
                    }
                    echo '✅ Docker Hub push tamamlandı'
                }
            }
        }
/*
        stage('Push to AWS ECR') {
            steps {
                script {
                    echo '📤 AWS ECR\'a image push ediliyor...'
                    sh """
                        # ECR login (IAM role otomatik kullanılır)
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Push to ECR
                        docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                    """
                    echo '✅ ECR push tamamlandı'
                }
            }
        }

        stage('Update K8s Manifest') {
            steps {
                script {
                    echo '📝 Kubernetes manifest güncelleniyor...'
                    withCredentials([string(credentialsId: 'GITHUB_TOKEN', variable: 'GIT_TOKEN')]) {
                        sh """
                            # Clone manifest repository
                            rm -rf k8s-manifests
                            git clone https://\${GIT_TOKEN}@github.com/sadikgok/k8s-manifests.git
                            cd k8s-manifests
                            
                            # Update image tag
                            sed -i 's|image: .*|image: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}|g' deployment.yaml
                            
                            # Commit and push
                            git config user.email "jenkins@pipeline.com"
                            git config user.name "Jenkins Pipeline"
                            git add deployment.yaml
                            git commit -m "Update image to ${IMAGE_TAG}" || true
                            git push origin main || git push origin master
                            
                            cd ..
                            rm -rf k8s-manifests
                        """
                    }
                    echo '✅ Manifest güncellendi, ArgoCD otomatik sync yapacak'
                }
            }
        }

        stage('Cleanup Old Docker Tags') {
            steps {
                script {
                    echo '🧹 Eski Docker Hub tag\'leri temizleniyor...'
                    withCredentials([usernamePassword(
                        credentialsId: env.DOCKER_ID_LOGIN,
                        usernameVariable: 'HUB_USER',
                        passwordVariable: 'HUB_PAT'
                    )]) {
                        sh '''#!/usr/bin/env bash
                            set -euo pipefail
                            
                            REPO_NAME="${IMAGE_NAME}"
                            
                            # Get JWT token
                            HUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST \
                                -d "{\\"username\\": \\"$HUB_USER\\", \\"password\\": \\"$HUB_PAT\\"}" \
                                https://hub.docker.com/v2/users/login/ | jq -r .token)

                            if [ -z "$HUB_TOKEN" ] || [ "$HUB_TOKEN" = "null" ]; then
                                echo "❌ JWT token alınamadı"
                                exit 0
                            fi
                            
                            # Get all tags
                            ALL_TAGS=$(curl -s -H "Authorization: JWT ${HUB_TOKEN}" \
                                "https://hub.docker.com/v2/repositories/$REPO_NAME/tags/?page_size=1000" \
                                | jq -r '.results[].name')

                            if [ -z "$ALL_TAGS" ]; then
                                echo "⚠️ Tag bulunamadı"
                                exit 0
                            fi

                            # Keep last N tags, delete rest
                            TAGS_TO_DELETE=$(echo "$ALL_TAGS" | grep -v 'latest' | sort -rV | tail -n +$((${KEEP_COUNT} + 1)))
                            
                            if [ -z "$TAGS_TO_DELETE" ]; then
                                echo "✅ Silinecek tag yok"
                                exit 0
                            fi

                            echo "Silinecek tag'ler: $TAGS_TO_DELETE"
                            
                            echo "$TAGS_TO_DELETE" | while read TAG; do
                                echo "🗑️  Siliniyor: ${TAG}"
                                curl -s -X DELETE \
                                    -H "Authorization: JWT ${HUB_TOKEN}" \
                                    "https://hub.docker.com/v2/repositories/$REPO_NAME/tags/${TAG}/"
                            done
                            
                            echo "✅ Temizleme tamamlandı"
                        '''
                    }
                }
            }
        }

        stage('Cleanup Local Images') {
            steps {
                script {
                    echo '🧹 Yerel Docker image\'ları temizleniyor...'
                    sh """
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                        docker rmi ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG} || true
                        docker system prune -f || true
                    """
                }
            }
        }
        */
    }
    
    /*
    post {
        success {
            echo '✅ Pipeline başarıyla tamamlandı!'
            echo "📦 Docker Hub: ${IMAGE_NAME}:${IMAGE_TAG}"
            echo "📦 ECR: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo '❌ Pipeline başarısız oldu!'
        }
        always {
            echo '📋 Pipeline sonlandı'
            // Trivy raporlarını arşivle
            archiveArtifacts artifacts: "trivy-*.json, trivy-*.html, trivy-*.txt", 
                            allowEmptyArchive: true
        }
    }
    */
}
