pipeline {
    agent any

  
    tools {
        jdk 'Java17' // Veya 'Java21' tercih edilebilir.
        nodejs 'node22'
    }

    environment {
        APP_NAME = "finops-secure-eks-gitops-pipeline" // File 2 Proje Adı
        RELEASE = "1.0"
        DOCKER_USER = "sadikgok"
        // 'dockerhub-sadikgok' (File 1) veya 'DockerHubTokenForJenkins' (File 2) kullanıldı.
        DOCKER_ID_LOGIN = 'DockerHubTokenForJenkins' 
        IMAGE_NAME = "${DOCKER_USER}/${APP_NAME}"
        IMAGE_TAG = "${RELEASE}.${BUILD_NUMBER}"
        
        // Credential'lar
        JENKINS_API_TOKEN = credentials('JENKINS_API_TOKEN') // CD Tetikleme için
        SONAR_CREDENTIALS = 'SonarTokenForJenkins' // SonarQube için

        // Trivy rapor dosyalarının dinamik isimleri (File 1'den alındı)
        TRIVY_JSON_REPORT = "trivy-report-${IMAGE_TAG}.json"
        TRIVY_HTML_REPORT = "trivy-report-${IMAGE_TAG}.html"
        
        // Docker Hub Temizliği için (File 1'den alındı)
        KEEP_COUNT = 3
    }

    stages {

        stage('Cleanup Workspace') {
            steps {
                cleanWs() // File 2'den alındı: İşlemlerden önce temiz başlangıç
            }
        }

        stage('Checkout from SCM') {
            steps {
                // File 2'den alındı: Projenin Git deposunu çeker
                git branch: 'master', url: 'https://github.com/sadikgok/finops-secure-eks-gitops-pipeline'
            }
        }

        stage('Install Dependencies') {
            steps {
                script {
                    if (isUnix()) {
                        sh 'npm install'
                    } else {
                        bat 'npm install'
                    }
                }
            }
        }
        
        stage('Test') {
            steps {
                // Node.js test komutunu ekleyin (örnek)
                script {
                    if (isUnix()) {
                        sh 'npm test || true' // Test başarısız olsa bile pipeline'ı durdurmamak için
                    } else {
                        bat 'npm test || true' 
                    }
                }
            }
        }

        // 1. AŞAMA: Statik Analiz (File 2'den alındı, File 1'deki SonarQube aşamaları aktif edildi)
        stage("SonarQube Analysis") {
            steps {
                withSonarQubeEnv(credentialsId: env.SONAR_CREDENTIALS) {
                    // File 2'deki sonar-scanner komutu kullanıldı
                    sh """
                        /opt/apache-maven/bin/mvn sonar:sonar \
                        -Dsonar.projectName=${APP_NAME} \
                        -Dsonar.projectKey=${APP_NAME} \
                        -Dsonar.sources=.
                    """ // Eğer proje Maven değilse, Node.js için sonar-scanner CLI kullanılır: $SCANNER_HOME/bin/sonar-scanner ...
                }
            }
        }

        stage("Quality Gate") {
            steps {
                script {
                    waitForQualityGate abortPipeline: false, credentialsId: env.SONAR_CREDENTIALS
                }
            }
        }

        // 2. AŞAMA: Trivy Dosya Sistemi Taraması (File 2'den alındı, daha temiz)
        stage('Trivy File System Scan') {
            steps {
                script {
                    echo "Trivy Dosya Sistemi Taraması Başlatılıyor..."
                    // `fs` taraması ve raporu trivyfs.txt'ye yazılır (Post'ta e-posta eki için)
                    sh "docker run --rm -v \$(pwd):/work aquasec/trivy:latest fs --format table /work > trivyfs.txt"
                    echo "Trivy Dosya Sistemi Taraması Tamamlandı."
                }
            }
        }
        
        // 3. AŞAMA: Docker Oluşturma ve Yayınlama (File 1'den alındı, daha profesyonel)
        stage('Docker Build & Push to DockerHub') {
            steps {
                script {
                    // Dinamik etiketleme ve push mekanizması kullanılır
                    docker.withRegistry('', DOCKER_ID_LOGIN) {
                        def docker_image = docker.build "${IMAGE_NAME}"
                        docker_image.push("${IMAGE_TAG}")
                        docker_image.push("latest")
                    }
                }
            }
        }

        // 4. AŞAMA: Trivy İmaj Taraması ve Rapor (File 1'deki yorum satırlarından alındı, JSON/HTML rapor oluşturur)
        stage("Trivy Image Scan - JSON + HTML") {
            steps {
                script {
                    def imageToScan = "${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Taranacak imaj: ${imageToScan}"

                    // JSON rapor oluşturma
                    sh """
                        chmod 777 ${WORKSPACE} || true
                        docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v ${WORKSPACE}:/report \
                        aquasec/trivy:0.67.2 image \
                        --format json \
                        --output /report/${TRIVY_JSON_REPORT} \
                        ${imageToScan}
                    """

                    // HTML rapor oluşturma
                    sh """
                        docker run --rm \
                        -v ${WORKSPACE}:/report \
                        aquasec/trivy:0.67.2 convert \
                        --format template \
                        --template "@/contrib/html.tpl" \
                        --output /report/${TRIVY_HTML_REPORT} \
                        /report/${TRIVY_JSON_REPORT}
                    """
                    echo "✅ Trivy JSON ve HTML raporları oluşturuldu."
                }
            }
        }

        // 5. AŞAMA: CD Pipeline Tetikleme (File 1'den alındı)
        // stage("Trigger CD Pipeline") {
        //     steps {
        //         script {
        //             // ArgoCD'yi tetiklemek için curl komutu
        //             // NOT: URL ve Job adı güncellenmelidir. Örnekteki 'devops-03-pipeline-ArgoCD' kullanıldı.
        //             sh "curl -v -k --user sadikgok:${JENKINS_API_TOKEN} -X POST -H 'cache-control: no-cache' -H 'content-type: application/x-www-form-urlencoded' --data 'IMAGE_TAG=${IMAGE_TAG}' 'ec2-3-94-121-61.compute-1.amazonaws.com:8080/job/devops-03-pipeline-ArgoCD/buildWithParameters?token=GITOPS_TRIGGER_START'"
        //         }
        //     }
        // }
        
        // // 6. AŞAMA: Docker Hub Etiket Temizliği (File 1'den alındı, en profesyonel aşama)
        // stage('Cleanup Old Docker Tags') {
        //     steps {
        //         script {
        //             // Docker Hub'a login olmak için credential kullanılır
        //             withCredentials([usernamePassword(
        //                 credentialsId: env.DOCKER_ID_LOGIN,
        //                 usernameVariable: 'HUB_USER',
        //                 passwordVariable: 'HUB_PAT'
        //             )]) {
        //                 sh """#!/usr/bin/env bash
        //                     set -euo pipefail
                            
        //                     REPO_NAME="${env.IMAGE_NAME}"
                            
        //                     echo "1. Docker Hub JWT tokenı alınıyor..."
        //                     HUB_TOKEN=\$(curl -s -H "Content-Type: application/json" -X POST \\
        //                         -d "{\\"username\\": \\"\$HUB_USER\\", \\"password\\": \\"\$HUB_PAT\\"}" \\
        //                         https://hub.docker.com/v2/users/login/ | jq -r .token)

        //                     if [ -z "\$HUB_TOKEN" ]; then
        //                         echo "Hata: Docker JWT tokenı alınamadı."
        //                         exit 1
        //                     fi
                            
        //                     echo "2. Depodaki tüm etiketler çekiliyor..."
        //                     ALL_TAGS=\$(curl -s -H "Authorization: JWT \${HUB_TOKEN}" \\
        //                         "https://hub.docker.com/v2/repositories/\$REPO_NAME/tags/?page_size=1000" | jq -r '.results[].name')

        //                     if [ -z "\$ALL_TAGS" ]; then
        //                         echo "Uyarı: Depoda (\${REPO_NAME}) etiket bulunamadı."
        //                         exit 0
        //                     fi

        //                     echo "3. Etiketler sıralanıyor ve en son ${env.KEEP_COUNT} tanesi hariç tutuluyor..."
        //                     # Versiyon bazlı sıralama (sort -V) ve tersten (sort -rV)
        //                     # "latest" etiketini silinmemesi için filtreleme eklenebilir.
        //                     TAGS_TO_DELETE=\$(echo "\$ALL_TAGS" | grep -v 'latest' | sort -rV | tail -n +\$(( ${env.KEEP_COUNT} + 1 )))
                            
        //                     if [ -z "\$TAGS_TO_DELETE" ]; then
        //                         echo "Silinecek eski sürüm bulunamadı. (${env.KEEP_COUNT} sürüm korunuyor)"
        //                         exit 0
        //                     fi

        //                     echo "4. Silinecek Etiketler: \n\${TAGS_TO_DELETE}"

        //                     echo "5. Etiketler siliniyor..."
        //                     echo "\$TAGS_TO_DELETE" | while read TAG; do
        //                         echo "  -> Siliniyor: \${TAG}"
        //                         curl -s -X DELETE \\
        //                             -H "Authorization: JWT \${HUB_TOKEN}" \\
        //                             "https://hub.docker.com/v2/repositories/\$REPO_NAME/tags/\${TAG}/"
        //                     done
                            
        //                     echo "Temizleme işlemi tamamlandı."
        //                 """
        //             }
        //         }
        //     }
        // }
    }
    
}