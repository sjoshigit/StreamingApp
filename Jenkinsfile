pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-south-1'
        CLUSTER_NAME   = 'streaming-cluster'
        IMAGE_TAG      = "1.0.${BUILD_NUMBER}"
        AWS_ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
        ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    }

    stages {

        // ------------------------------------------------------------
        // 1. Checkout source code
        // ------------------------------------------------------------
        stage('Checkout Code') {
            steps {
                echo 'Checking out StreamingApp source code...'
                checkout scm
            }
        }

        // ------------------------------------------------------------
        // 2. Get AWS Account ID from EC2 IAM Role
        // ------------------------------------------------------------
        stage('Get AWS Account ID') {
            steps {
                script {
                    env.AWS_ACCOUNT_ID = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim()

                    env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

                    echo "AWS Region   : ${env.AWS_REGION}"
                    echo "Cluster Name : ${env.CLUSTER_NAME}"
                    echo "AWS Account  : ${env.AWS_ACCOUNT_ID}"
                    echo "ECR Registry : ${env.ECR_REGISTRY}"
                    echo "Image Tag    : ${env.IMAGE_TAG}"
                }
            }
        }

        // ------------------------------------------------------------
        // 3. Verify AWS, Docker, and Kubernetes tools
        // ------------------------------------------------------------
        stage('Verify Environment') {
            steps {
                sh '''
                    set -eux
                    aws --version
                    aws sts get-caller-identity
                    docker --version
                    kubectl version --client
                    helm version
                '''
            }
        }

        // ------------------------------------------------------------
        // 4. Create ECR repositories if missing
        // ------------------------------------------------------------
        stage('Provision ECR Repositories') {
            steps {
                sh '''
                    set -eu

                    repositories="
                    streaming-auth
                    streaming-stream
                    streaming-admin
                    streaming-chat
                    streaming-frontend
                    "

                    for repo in $repositories; do
                        if aws ecr describe-repositories \
                            --repository-names "$repo" \
                            --region "$AWS_REGION" \
                            >/dev/null 2>&1
                        then
                            echo "ECR repository '$repo' already exists. Skipping."
                        else
                            echo "Creating ECR repository '$repo'..."
                            aws ecr create-repository \
                                --repository-name "$repo" \
                                --region "$AWS_REGION" \
                                --image-scanning-configuration scanOnPush=true
                        fi
                    done
                '''
            }
        }

        // ------------------------------------------------------------
        // 5. Authenticate Docker with AWS ECR
        // ------------------------------------------------------------
        stage('Authenticate to ECR') {
            steps {
                sh '''
                    set -eux
                    aws ecr get-login-password --region "$AWS_REGION" | \
                        docker login --username AWS --password-stdin "$ECR_REGISTRY"
                '''
            }
        }

        // ------------------------------------------------------------
        // 6. Build and push all five services in parallel
        // ------------------------------------------------------------
        stage('Build & Push Images to ECR') {
            parallel {

                stage('Auth Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build -t "${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}" backend/authService
                            docker push "${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}"
                        '''
                    }
                }

                stage('Streaming Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build -t "${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}" -f backend/streamingService/Dockerfile backend
                            docker push "${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}"
                        '''
                    }
                }

                stage('Admin Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build -t "${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}" -f backend/adminService/Dockerfile backend
                            docker push "${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}"
                        '''
                    }
                }

                stage('Chat Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build -t "${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}" -f backend/chatService/Dockerfile backend
                            docker push "${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}"
                        '''
                    }
                }

                stage('Frontend') {
                    steps {
                        sh '''
                            set -eux

                            # Generate .env directly on the agent to override gitignored config
                            cat << 'EOF' > frontend/.env
REACT_APP_AUTH_API_URL=/api/auth
REACT_APP_STREAMING_API_URL=/api/streaming
REACT_APP_STREAMING_PUBLIC_URL=/api/streaming
REACT_APP_ADMIN_API_URL=/api/admin
REACT_APP_CHAT_API_URL=/api/chat
REACT_APP_CHAT_SOCKET_URL=/
EOF

                            # Build with args matching the Ingress routing rules
                            docker build \
                                --build-arg REACT_APP_AUTH_API_URL="/api/auth" \
                                --build-arg REACT_APP_STREAMING_API_URL="/api/streaming" \
                                --build-arg REACT_APP_STREAMING_PUBLIC_URL="/api/streaming" \
                                --build-arg REACT_APP_ADMIN_API_URL="/api/admin" \
                                --build-arg REACT_APP_CHAT_API_URL="/api/chat" \
                                --build-arg REACT_APP_CHAT_SOCKET_URL="/" \
                                -t "${ECR_REGISTRY}/streaming-frontend:${IMAGE_TAG}" \
                                frontend

                            docker push "${ECR_REGISTRY}/streaming-frontend:${IMAGE_TAG}"
                        '''
                    }
                }
            }
        }

        // ------------------------------------------------------------
        // 7. Verify images in ECR
        // ------------------------------------------------------------
        stage('Verify ECR Images') {
            steps {
                sh '''
                    set -eux
                    for repo in streaming-auth streaming-stream streaming-admin streaming-chat streaming-frontend; do
                        aws ecr describe-images \
                            --repository-name "$repo" \
                            --region "$AWS_REGION" \
                            --image-ids imageTag="$IMAGE_TAG" \
                            --query 'imageDetails[0].{Repository:repositoryName,Tag:imageTags[0]}' \
                            --output table
                    done
                '''
            }
        }

        // ------------------------------------------------------------
        // 8. Connect to EKS Cluster
        // ------------------------------------------------------------
        stage('Configure EKS Kubeconfig') {
            steps {
                sh '''
                    set -eux
                    echo "Updating kubeconfig for ${CLUSTER_NAME} in ${AWS_REGION}..."
                    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
                    
                    echo "Verifying cluster nodes..."
                    kubectl get nodes
                '''
            }
        }

        // ------------------------------------------------------------
        // 9. Deploy / Upgrade using Helm Chart
        // ------------------------------------------------------------
        stage('Deploy via Helm') {
            steps {
                sh '''
                    set -eux
                    echo "Deploying StreamingApp via Helm to ${CLUSTER_NAME}..."

                    helm upgrade --install streamingapp ./streamingapp \
                      --set services.auth.image="${ECR_REGISTRY}/streaming-auth" \
                      --set services.auth.tag="${IMAGE_TAG}" \
                      --set services.streaming.image="${ECR_REGISTRY}/streaming-stream" \
                      --set services.streaming.tag="${IMAGE_TAG}" \
                      --set services.admin.image="${ECR_REGISTRY}/streaming-admin" \
                      --set services.admin.tag="${IMAGE_TAG}" \
                      --set services.chat.image="${ECR_REGISTRY}/streaming-chat" \
                      --set services.chat.tag="${IMAGE_TAG}" \
                      --set services.frontend.image="${ECR_REGISTRY}/streaming-frontend" \
                      --set services.frontend.tag="${IMAGE_TAG}"

                    echo "Helm deployment submitted successfully."
                '''
            }
        }

        // ------------------------------------------------------------
        // 10. Verify Deployment Rollout Status
        // ------------------------------------------------------------
        stage('Verify Rollout') {
            steps {
                sh '''
                    set -eux
                    echo "Checking rollout status for microservices..."
                    kubectl rollout status deployment/auth-deployment --timeout=120s
                    kubectl rollout status deployment/streaming-deployment --timeout=120s
                    kubectl rollout status deployment/admin-deployment --timeout=120s
                    kubectl rollout status deployment/chat-deployment --timeout=120s
                    kubectl rollout status deployment/frontend-deployment --timeout=120s

                    echo "Current pod status:"
                    kubectl get pods
                '''
            }
        }
    }

    post {
        always {
            echo 'Cleaning unused Docker build layers...'
            sh 'docker image prune -f || true'
        }

        success {
            echo """
============================================================
PIPELINE SUCCESS
============================================================
All 5 images built with relative Ingress paths and deployed to EKS!

Cluster   : ${CLUSTER_NAME} (${AWS_REGION})
Image Tag : ${IMAGE_TAG}
ECR       : ${ECR_REGISTRY}
============================================================
"""
        }

        failure {
            echo '''
============================================================
PIPELINE FAILED
============================================================
Deployment failed. Check the Jenkins console log for errors.
============================================================
'''
        }
    }
}