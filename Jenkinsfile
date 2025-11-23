pipeline {
    agent any


    tools {
        jdk 'JDK17'
        nodejs 'node22'
    }

   environment {
        SCANNER_HOME = tool "sonar-scanner"
    }


    stages {

         stage('Cleanup Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout from SCM') {
            steps {
                git branch: 'master',  url: 'https://github.com/sadikgok/devops-05-pipeline-aws-1'
            }
        }

        stage('Install Dependencies') {
            steps {
                 script {
                    if (isUnix()) {
                            sh 'npm install'
                        } else  {
                            bat 'npm install'
                     }
                 }
            }
        }


        stage("Sonarqube Analysis") {
            steps {
                withSonarQubeEnv('SonarTokenForJenkins') {
                    sh """
                        $SCANNER_HOME/bin/sonar-scanner \
                        -Dsonar.projectName=devops-05-pipeline-aws \
                        -Dsonar.projectKey=devops-05-pipeline-aws
                    """
                }
            }
        }


       stage("Quality Gate"){
           steps {
               script {
                    waitForQualityGate abortPipeline: false, credentialsId: 'SonarTokenForJenkins'
                }
            }
        }



         stage("Trivy File System Scan"){
            steps{
                // sh "trivy fs . > trivyfs.txt"
                script {
                    if (isUnix()) {
                        withEnv(["TRIVY_CACHE_DIR=${WORKSPACE}/.trivy-cache"]) {
                            sh 'trivy fs . > trivyfs.txt'
                        }
                    } else  {
                        bat 'set TRIVY_CACHE_DIR=%cd%\\.trivy-cache && trivy fs . > trivyfs.txt'
                     }
                 }
            }
        }


   
        stage("Docker Build & Push"){
    steps{
        script{
            withDockerRegistry(credentialsId: 'DockerHubTokenForJenkins', toolName: 'docker'){
                  // İmajı oluştur
                sh "docker build -t devops-05-pipeline-aws ."
                // Oluşturulan imaja tam hedef etiketi ver
                sh "docker tag devops-05-pipeline-aws sadikgok/devops-05-pipeline-aws-1:latest" 
                // Tam etiketli imajı push et
                sh "docker push sadikgok/devops-05-pipeline-aws-1:latest" 
            }
        }
    }
}


  
        stage("Trivy Image Scan"){
            steps{
                script {
                    withEnv([
                        "TRIVY_CACHE_DIR=${WORKSPACE}/.trivy-cache", // DB önbelleği için
                        "TRIVY_TEMP_DIR=${WORKSPACE}/.trivy-temp"  ]) {
                        sh "trivy image sadikgok/devops-05-pipeline-aws-1:latest > trivyimage.txt"
                    }
                }
            }
        }
        
/* 

        stage('Deploy to Kubernetes'){
            steps{
                script{
                    dir('kubernetes') {
                      withKubeConfig(caCertificate: '', clusterName: '', contextName: '', credentialsId: 'kubernetes', namespace: '', restrictKubeConfigAccess: false, serverUrl: '') {
                          sh 'kubectl delete --all pods'
                          sh 'kubectl apply -f deployment.yml'
                          sh 'kubectl apply -f service.yml'
                      }
                    }
                }
            }
        }
*/


        stage('Docker Image to Clean') {
            steps {
                // sh 'docker rmi mimaraslan/devops-05-pipeline-aws:latest'
                sh 'docker image prune -f --filter "dangling=true"'
            }
        }


    }



    post {
     always {
        emailext attachLog: true,
            subject: "'${currentBuild.result}'",
            body: "Project: ${env.JOB_NAME}<br/>" +
                "Build Number: ${env.BUILD_NUMBER}<br/>" +
                "URL: ${env.BUILD_URL}<br/>",
            to: 'sadik.gok@gmail.com',
            attachmentsPattern: 'trivyfs.txt,trivyimage.txt'
        }
    }


}