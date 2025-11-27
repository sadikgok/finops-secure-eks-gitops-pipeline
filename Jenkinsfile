pipeline {
    agent any

    tools {
        jdk 'Java17'
        nodejs 'node22'
    }

    environment {
        APP_NAME = "finops-secure-eks-gitops-pipeline"
        RELEASE = "1.0"
        DOCKER_USER = "sadikgok"
        DOCKER_ID_LOGIN = 'DockerHubTokenForJenkins'
        IMAGE_NAME = "${DOCKER_USER}/${APP_NAME}"
        IMAGE_TAG = "${RELEASE}.${BUILD_NUMBER}"
        
        // AWS/ECR Bilgileri (Terraform çıktısından alınacak)
        //AWS_REGION = "ap-south-1"
        //AWS_ACCOUNT_ID = credentials('AWS_ACCOUNT_ID') // Jenkins'te credential olarak ekleyin
        //ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        //ECR_REPO_NAME = "myapp-repo"
        
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
                git branch: 'master', 
                    url: 'https://github.com/sadikgok/finops-secure-eks-gitops-pipeline'
                echo '✅ Kod deposu klonlandı'
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    echo 'Bağımlılıklar yükleniyor...'
                    if (isUnix()) {
                        sh 'npm install'
                    } else {
                        bat 'npm install'
                    }
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                script {
                    echo ' Testler çalıştırılıyor...'
                    if (isUnix()) {
                        sh 'npm test || true'
                    } else {
                        bat 'npm test || true'
                    }
                }
            }
        }

        stage("SonarQube Analysis") {
            steps {
                script {
                    echo ' SonarQube kod analizi başlatılıyor...'
                    withSonarQubeEnv(credentialsId: env.SONAR_CREDENTIALS) {
                        // Node.js projesi için sonar-scanner kullanımı
                        sh """
                            docker run --rm \
                                --network sonarnet \
                                -v \${WORKSPACE}:/usr/src \
                                -e SONAR_HOST_URL=http://sonar:9000 \
                                -e SONAR_LOGIN=\${SONAR_AUTH_TOKEN} \
                                sonarsource/sonar-scanner-cli \
                                -Dsonar.projectKey=${APP_NAME} \
                                -Dsonar.projectName=${APP_NAME} \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=node_modules/**,test/**
                        """
                    }
                }
            }
        }

        stage("Quality Gate") {
            steps {
                script {
                    echo ' Quality Gate kontrol ediliyor...'
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
                    echo ' Trivy dosya sistemi taraması başlatılıyor...'
                    sh """
                        docker run --rm \
                            -v \$(pwd):/work \
                            aquasec/trivy:latest fs \
                            --severity HIGH,CRITICAL \
                            --format table \
                            /work > ${TRIVY_FS_REPORT}
                    """
                    echo '✅ Trivy FS taraması tamamlandı'
                }
            }
        }
        
        stage('Docker Build & Tag') {
            steps {
                script {
                    echo ' Docker image build ediliyor...'
                    // Hem Docker Hub hem ECR için tag'le
                    sh """
                        docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                    """
                    echo ' Docker image oluşturuldu ve tag\'lendi'
                }
            }
        }

        stage("Trivy Image Scan") {
            steps {
                script {
                    echo '🔍 Trivy image güvenlik taraması başlatılıyor...'
                    
                    // JSON rapor oluştur
                    sh """
                        chmod 777 ${WORKSPACE} || true
                        docker run --rm \
                            -v /var/run/docker.sock:/var/run/docker.sock \
                            -v ${WORKSPACE}:/report \
                            aquasec/trivy:latest image \
                            --format json \
                            --severity HIGH,CRITICAL \
                            --output /report/${TRIVY_JSON_REPORT} \
                            ${IMAGE_NAME}:${IMAGE_TAG}
                    """

                    // HTML rapor oluştur
                    sh """
                        docker run --rm \
                            -v ${WORKSPACE}:/report \
                            aquasec/trivy:latest convert \
                            --format template \
                            --template "@contrib/html.tpl" \
                            --output /report/${TRIVY_HTML_REPORT} \
                            /report/${TRIVY_JSON_REPORT}
                    """
                    
                    echo '✅ Trivy güvenlik raporları oluşturuldu'
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                script {
                    echo ' Docker Hub\'a image push ediliyor...'
                    docker.withRegistry('https://registry.hub.docker.com', DOCKER_ID_LOGIN) {
                        sh """
                            docker push ${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${IMAGE_NAME}:latest
                        """
                    }
                    echo '✅ Docker Hub push tamamlandı'
                }
            }
        }

        stage('Push to AWS ECR') {
            steps {
                script {
                    echo ' AWS ECR\'a image push ediliyor...'
                    sh """
                        # ECR login
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
                    // ArgoCD için GitOps repository'sini güncelle
                    sh """
                        # Manifest repo'sunu clone et
                        git clone https://github.com/sadikgok/k8s-manifests.git
                        cd k8s-manifests
                        
                        # Image tag'ini güncelle
                        sed -i 's|image: .*|image: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}|g' deployment.yaml
                        
                        # Değişiklikleri commit ve push et
                        git config user.email "jenkins@pipeline.com"
                        git config user.name "Jenkins Pipeline"
                        git add deployment.yaml
                        git commit -m "Update image to ${IMAGE_TAG}" || true
                        git push origin main
                    """
                    echo '✅ Manifest güncellendi, ArgoCD otomatik sync yapacak'
                }
            }
        }

        stage('Cleanup Old Docker Tags') {
            steps {
                script {
                    echo '🧹 Eski Docker image tag\'leri temizleniyor...'
                    withCredentials([usernamePassword(
                        credentialsId: env.DOCKER_ID_LOGIN,
                        usernameVariable: 'HUB_USER',
                        passwordVariable: 'HUB_PAT'
                    )]) {
                        sh """#!/usr/bin/env bash
                            set -euo pipefail
                            
                            REPO_NAME="${env.IMAGE_NAME}"
                            
                            echo "1. Docker Hub JWT token alınıyor..."
                            HUB_TOKEN=\$(curl -s -H "Content-Type: application/json" -X POST \\
                                -d "{\\"username\\": \\"\$HUB_USER\\", \\"password\\": \\"\$HUB_PAT\\"}" \\
                                https://hub.docker.com/v2/users/login/ | jq -r .token)

                            if [ -z "\$HUB_TOKEN" ] || [ "\$HUB_TOKEN" = "null" ]; then
                                echo "❌ JWT token alınamadı"
                                exit 1
                            fi
                            
                            echo "2. Tüm tag'ler çekiliyor..."
                            ALL_TAGS=\$(curl -s -H "Authorization: JWT \${HUB_TOKEN}" \\
                                "https://hub.docker.com/v2/repositories/\$REPO_NAME/tags/?page_size=1000" \\
                                | jq -r '.results[].name')

                            if [ -z "\$ALL_TAGS" ]; then
                                echo "⚠️ Depoda tag bulunamadı"
                                exit 0
                            fi

                            echo "3. En son ${env.KEEP_COUNT} tag hariç eskiler belirleniyor..."
                            TAGS_TO_DELETE=\$(echo "\$ALL_TAGS" | grep -v 'latest' | sort -rV | tail -n +\$(( ${env.KEEP_COUNT} + 1 )))
                            
                            if [ -z "\$TAGS_TO_DELETE" ]; then
                                echo "✅ Silinecek tag yok (${env.KEEP_COUNT} adet korunuyor)"
                                exit 0
                            fi

                            echo "4. Silinecek tag'ler:"
                            echo "\$TAGS_TO_DELETE"

                            echo "5. Tag'ler siliniyor..."
                            echo "\$TAGS_TO_DELETE" | while read TAG; do
                                echo "  🗑️  Siliniyor: \${TAG}"
                                curl -s -X DELETE \\
                                    -H "Authorization: JWT \${HUB_TOKEN}" \\
                                    "https://hub.docker.com/v2/repositories/\$REPO_NAME/tags/\${TAG}/"
                            done
                            
                            echo "✅ Temizleme tamamlandı"
                        """
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
    }
    
    post {
        success {
            echo '✅ Pipeline başarıyla tamamlandı!'
            echo "📦 Image: ${IMAGE_NAME}:${IMAGE_TAG}"
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
}
