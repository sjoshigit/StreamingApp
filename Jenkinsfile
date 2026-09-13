pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-south-1'
        // Dynamically get the AWS Account ID from the attached EC2 IAM Role
        AWS_ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
        ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_TAG      = "1.0.${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Provision ECR Repositories') {
            steps {
                // POSIX-compliant loop compatible with dash (/bin/sh)
                sh '''
                for repo in streaming-auth streaming-stream streaming-admin streaming-chat streaming-frontend; do
                  if aws ecr describe-repositories --repository-names "$repo" --region "${AWS_REGION}" >/dev/null 2>&1; then
                    echo "ECR repository '$repo' already exists in ${AWS_REGION}. Skipping creation."
                  else
                    echo "Creating ECR repository '$repo' in ${AWS_REGION}..."
                    aws ecr create-repository \
                      --repository-name "$repo" \
                      --region "${AWS_REGION}" \
                      --image-scanning-configuration scanOnPush=true
                  fi
                done
                '''
            }
        }

        stage('Authenticate to ECR') {
            steps {
                // Fetch authorization token and authenticate Docker with ECR in ap-south-1
                sh 'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}'
            }
        }

        stage('Build & Push Images to ECR') {
            parallel {
                stage('Auth Service') {
                    steps {
                        sh "docker build -t ${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG} backend/authService"
                        sh "docker push ${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}"
                    }
                }
                stage('Streaming Service') {
                    steps {
                        sh "docker build -t ${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG} -f backend/streamingService/Dockerfile backend"
                        sh "docker push ${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}"
                    }
                }
                stage('Admin Service') {
                    steps {
                        sh "docker build -t ${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG} -f backend/adminService/Dockerfile backend"
                        sh "docker push ${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}"
                    }
                }
                stage('Chat Service') {
                    steps {
                        sh "docker build -t ${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG} -f backend/chatService/Dockerfile backend"
                        sh "docker push ${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}"
                    }
                }
                stage('Frontend') {
                    steps {
                        sh "docker build -t ${ECR_REGISTRY}/streaming-frontend:${IMAGE_TAG} frontend"
                        sh "docker push ${ECR_REGISTRY}/streaming-frontend:${IMAGE_TAG}"
                    }
                }
            }
        }
    }

    post {
        always {
            // Prune local build layers on the EC2 build controller
            sh "docker image prune -f || true"
        }
        success {
            echo "Build successful! All 5 images published to ECR (${AWS_REGION}) with tag: ${IMAGE_TAG}"
        }
        failure {
            echo "Pipeline run failed. Inspect console logs for details."
        }
    }
}