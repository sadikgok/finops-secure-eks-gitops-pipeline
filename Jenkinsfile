pipeline {
    agent any

    tools {
        jdk 'java17'
        nodejs 'node22'
    }

    environment {
        SONAR_SERVER_NAME = 'SonarQube'
        SONAR_PROJECT_KEY = 'end-to-end-pipeline'
        SCANNER_HOME      = tool 'SonarQubeScanner'
        
        // DockerHub Bilgileri
        DOCKER_USER       = "sadikgok"
        DOCKER_REPO       = "finops-secure-eks-gitops-pipeline" // DockerHub'daki repository adın
        IMAGE_TAG         = "${BUILD_NUMBER}"
        DOCKER_IMAGE      = "${DOCKER_USER}/${DOCKER_REPO}:${IMAGE_TAG}"
        
        // Credentials IDs (Jenkins > Credentials kısmındaki isimler)
        DOCKER_HUB_CREDS  = 'DockerHubTokenForJenkins' 
    }

    stages {
        stage('Cleanup & Checkout') {
            steps {
                cleanWs()
                git branch: 'main', url: 'https://github.com/sadikgok/finops-secure-eks-gitops-pipeline'
            }
        }
        
        stage('Install & Test') {
            steps {
                sh 'npm install'
                sh 'npm test || true'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv("${SONAR_SERVER_NAME}") {
                    sh "${SCANNER_HOME}/bin/sonar-scanner -Dsonar.projectKey=${SONAR_PROJECT_KEY} -Dsonar.sources=."
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Security Scan (Trivy FS)') {
            steps {
                // Kod seviyesinde tarama
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v ${WORKSPACE}:/rootfs aquasec/trivy:latest fs /rootfs --severity HIGH,CRITICAL"
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    // DockerHub'a Login ve Push
                    withCredentials([usernamePassword(credentialsId: "${DOCKER_HUB_CREDS}", passwordVariable: 'DOCKER_HUB_PASSWORD', usernameVariable: 'DOCKER_HUB_USER')]) {
                        sh "docker build -t ${DOCKER_IMAGE} ."
                        sh "echo \$DOCKER_HUB_PASSWORD | docker login -u \$DOCKER_HUB_USER --password-stdin"
                        sh "docker push ${DOCKER_IMAGE}"
                    }
                }
            }
        }

        stage('Security Scan (Trivy Image)') {
            steps {
                // Oluşturulan imajı tarıyoruz (Daha güvenli!)
                sh "docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL ${DOCKER_IMAGE}"
            }
        }
        
       stage('GitOps: Update & Push') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'GithubTokenForJenkins', passwordVariable: 'GIT_PASSWORD', usernameVariable: 'GIT_USERNAME')]) {
                        sh '''
                            # 1. Dosyayı dinamik olarak bul (Klasör adı Kubernetes veya kubernetes olsa da bulur)
                            DEPLOY_FILE=$(find . -name "deployment.y*ml" | head -n 1)
                            
                            if [ -z "$DEPLOY_FILE" ]; then
                                echo "❌ HATA: Deployment dosyası bulunamadı!"
                                exit 1
                            fi
                            
                            echo "🔍 Güncellenen dosya: $DEPLOY_FILE"

                            # 2. Güncelleme (sed komutunu bulduğumuz dosyaya uyguluyoruz)
                            sed -i "s|image: ${DOCKER_USER}/.*|image: ${DOCKER_IMAGE}|g" "$DEPLOY_FILE"
                            
                            # 3. Git İşlemleri (Tek tırnak içinde değişkenleri güvenli kullanıyoruz)
                            git config user.email "jenkins@example.com"
                            git config user.name "Jenkins Automation"
                            
                            git add "$DEPLOY_FILE"
                            # Değişiklik yoksa hata vermemesi için || true
                            git commit -m "chore: update image to ${DOCKER_IMAGE} [skip ci]" || echo "Değişiklik yok"
                            
                            # Push işlemi (Değişkenleri shell'den alıyoruz)
                            git push https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/sadikgok/finops-secure-eks-gitops-pipeline.git HEAD:main
                        '''
                    }
                }
            }
     
        }

        stage('Update Manifest (GitOps)') {
            steps {
                echo "🚀 Klasör yapısı kontrol ediliyor..."
                sh "ls -R" // Tüm alt klasörleri listeler, dosyanın tam yerini görürüz
                
                echo "🚀 ArgoCD için manifest güncelleniyor..."
                // 'kubernetes' klasörünün varlığından ve isminden emin olun (Büyük/küçük harf duyarlıdır)
                sh """
                    sed -i 's|image: ${DOCKER_USER}/${DOCKER_REPO}:.*|image: ${DOCKER_IMAGE}|g' kubernetes/deployment.yml
                """
                echo "✅ K8s manifest güncellendi: ${DOCKER_IMAGE}"
            }
        }
    }

    post {
        success {
            echo '✅ E2E Pipeline başarıyla tamamlandı! ArgoCD şimdi değişikliği fark edecek.'
        }
    }
}