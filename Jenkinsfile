pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-south-1'
        IMAGE_TAG      = "1.0.${BUILD_NUMBER}"
        // Dynamically get the AWS Account ID from the attached EC2 IAM Role
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
                    echo "AWS Account  : ${env.AWS_ACCOUNT_ID}"
                    echo "ECR Registry : ${env.ECR_REGISTRY}"
                    echo "Image Tag    : ${env.IMAGE_TAG}"
                }
            }
        }

        // ------------------------------------------------------------
        // 3. Verify AWS and Docker environment
        // ------------------------------------------------------------
        stage('Verify Environment') {
            steps {
                sh '''
                    set -eux
                    aws --version
                    aws sts get-caller-identity
                    docker --version
                '''
            }
        }

        // ------------------------------------------------------------
        // 4. Create ECR repositories if they don't already exist
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
        // 6. Build and push all five services
        // ------------------------------------------------------------
        stage('Build & Push Images to ECR') {
            parallel {

                // Auth Service
                stage('Auth Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build \
                                -t "${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}" \
                                backend/authService
                            docker push "${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}"
                        '''
                    }
                }

                // Streaming Service
                stage('Streaming Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build \
                                -t "${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}" \
                                -f backend/streamingService/Dockerfile \
                                backend
                            docker push "${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}"
                        '''
                    }
                }

                // Admin Service
                stage('Admin Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build \
                                -t "${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}" \
                                -f backend/adminService/Dockerfile \
                                backend
                            docker push "${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}"
                        '''
                    }
                }

                // Chat Service
                stage('Chat Service') {
                    steps {
                        sh '''
                            set -eux
                            docker build \
                                -t "${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}" \
                                -f backend/chatService/Dockerfile \
                                backend
                            docker push "${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}"
                        '''
                    }
                }

                // Frontend Service (Injects Ingress paths into the React production build)
                stage('Frontend') {
                    steps {
                        sh '''
                            set -eux

                            # Create .env dynamically for build runtime
                            cat << 'EOF' > frontend/.env
REACT_APP_AUTH_API_URL=/api/auth
REACT_APP_STREAMING_API_URL=/api/streaming
REACT_APP_STREAMING_PUBLIC_URL=/api/streaming
REACT_APP_ADMIN_API_URL=/api/admin
REACT_APP_CHAT_API_URL=/api/chat
REACT_APP_CHAT_SOCKET_URL=/
EOF

                            # Pass variables via Docker ARG to ensure they bake into static JS
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
    }

    // ------------------------------------------------------------
    // Post-build actions
    // ------------------------------------------------------------
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
All 5 StreamingApp images built with relative Ingress paths
and pushed to Amazon ECR.

AWS Region : ${AWS_REGION}
Tag        : ${IMAGE_TAG}
Registry   : ${ECR_REGISTRY}
============================================================
"""
        }

        failure {
            echo '''
============================================================
PIPELINE FAILED
============================================================
One or more builds or pushes failed. Check console output.
============================================================
'''
        }
    }
}