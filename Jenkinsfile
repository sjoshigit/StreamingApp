pipeline {
    agent any

    environment {
        AWS_REGION = 'ap-south-1'
        IMAGE_TAG  = "1.0.${BUILD_NUMBER}"
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
                        script: '''
                            aws sts get-caller-identity \
                            --query Account \
                            --output text
                        ''',
                        returnStdout: true
                    ).trim()

                    env.ECR_REGISTRY =
                        "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"

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

                    echo "========================================"
                    echo "AWS CLI"
                    echo "========================================"
                    aws --version

                    echo "========================================"
                    echo "AWS Identity"
                    echo "========================================"
                    aws sts get-caller-identity

                    echo "========================================"
                    echo "Docker"
                    echo "========================================"
                    docker --version

                    echo "========================================"
                    echo "Docker Info"
                    echo "========================================"
                    docker info

                    echo "========================================"
                    echo "Working Directory"
                    echo "========================================"
                    pwd

                    echo "========================================"
                    echo "Repository Files"
                    echo "========================================"
                    ls -la
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

                            echo "ECR repository '$repo' already exists."
                            echo "Skipping creation."

                        else

                            echo "Creating ECR repository '$repo'..."

                            aws ecr create-repository \
                                --repository-name "$repo" \
                                --region "$AWS_REGION" \
                                --image-scanning-configuration scanOnPush=true

                            echo "Repository '$repo' created successfully."

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

                    echo "Authenticating Docker with Amazon ECR..."

                    aws ecr get-login-password \
                        --region "$AWS_REGION" |
                    docker login \
                        --username AWS \
                        --password-stdin "$ECR_REGISTRY"

                    echo "Docker authentication successful."
                '''
            }
        }

        // ------------------------------------------------------------
        // 6. Build and push all five services
        // ------------------------------------------------------------
        stage('Build & Push Images to ECR') {

            parallel {

                // ----------------------------------------------------
                // Auth Service
                // ----------------------------------------------------
                stage('Auth Service') {
                    steps {
                        sh '''
                            set -eux

                            echo "========================================"
                            echo "AUTH SERVICE - BUILD"
                            echo "========================================"

                            docker build \
                                -t "${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}" \
                                backend/authService

                            echo "========================================"
                            echo "AUTH SERVICE - PUSH"
                            echo "========================================"

                            docker push \
                                "${ECR_REGISTRY}/streaming-auth:${IMAGE_TAG}"

                            echo "Auth Service pushed successfully."
                        '''
                    }
                }

                // ----------------------------------------------------
                // Streaming Service
                // ----------------------------------------------------
                stage('Streaming Service') {
                    steps {
                        sh '''
                            set -eux

                            echo "========================================"
                            echo "STREAMING SERVICE - BUILD"
                            echo "========================================"

                            docker build \
                                -t "${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}" \
                                -f backend/streamingService/Dockerfile \
                                backend

                            echo "========================================"
                            echo "STREAMING SERVICE - PUSH"
                            echo "========================================"

                            docker push \
                                "${ECR_REGISTRY}/streaming-stream:${IMAGE_TAG}"

                            echo "Streaming Service pushed successfully."
                        '''
                    }
                }

                // ----------------------------------------------------
                // Admin Service
                // ----------------------------------------------------
                stage('Admin Service') {
                    steps {
                        sh '''
                            set -eux

                            echo "========================================"
                            echo "ADMIN SERVICE - BUILD"
                            echo "========================================"

                            docker build \
                                -t "${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}" \
                                -f backend/adminService/Dockerfile \
                                backend

                            echo "========================================"
                            echo "ADMIN SERVICE - PUSH"
                            echo "========================================"

                            docker push \
                                "${ECR_REGISTRY}/streaming-admin:${IMAGE_TAG}"

                            echo "Admin Service pushed successfully."
                        '''
                    }
                }

                // ----------------------------------------------------
                // Chat Service
                // ----------------------------------------------------
                stage('Chat Service') {
                    steps {
                        sh '''
                            set -eux

                            echo "========================================"
                            echo "CHAT SERVICE - BUILD"
                            echo "========================================"

                            docker build \
                                -t "${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}" \
                                -f backend/chatService/Dockerfile \
                                backend

                            echo "========================================"
                            echo "CHAT SERVICE - PUSH"
                            echo "========================================"

                            docker push \
                                "${ECR_REGISTRY}/streaming-chat:${IMAGE_TAG}"

                            echo "Chat Service pushed successfully."
                        '''
                    }
                }

                // ----------------------------------------------------
                // Frontend
                // ----------------------------------------------------
                stage('Frontend') {
                    steps {
                        sh '''
                            set -eux

                            echo "========================================"
                            echo "FRONTEND - BUILD"
                            echo "========================================"

                            docker build \
                                -t "${ECR_REGISTRY}/streaming-frontend:${IMAGE_TAG}" \
                                frontend

                            echo "========================================"
                            echo "FRONTEND - PUSH"
                            echo "========================================"

                            docker push \
                                "${ECR_REGISTRY}/streaming-frontend:${IMAGE_TAG}"

                            echo "Frontend pushed successfully."
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

                    echo "========================================"
                    echo "VERIFYING ECR IMAGES"
                    echo "========================================"

                    for repo in \
                        streaming-auth \
                        streaming-stream \
                        streaming-admin \
                        streaming-chat \
                        streaming-frontend
                    do

                        echo ""
                        echo "Repository: $repo"

                        aws ecr describe-images \
                            --repository-name "$repo" \
                            --region "$AWS_REGION" \
                            --image-ids imageTag="$IMAGE_TAG" \
                            --query 'imageDetails[0].{Repository:repositoryName,Tag:imageTags[0],Digest:imageDigest}' \
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
            echo 'Cleaning unused Docker images...'

            sh '''
                docker image prune -f || true
            '''
        }

        success {
            echo '''
============================================================
PIPELINE SUCCESS
============================================================
All 5 StreamingApp Docker images were successfully
built and pushed to Amazon ECR.

AWS Region : ${AWS_REGION}
Tag        : ${IMAGE_TAG}

Images:
  streaming-auth
  streaming-stream
  streaming-admin
  streaming-chat
  streaming-frontend

ECR Registry:
  ${ECR_REGISTRY}

============================================================
'''
        }

        failure {
            echo '''
============================================================
PIPELINE FAILED
============================================================
One or more pipeline stages failed.

Check the Jenkins console output above for the
specific service or command that failed.
============================================================
'''
        }

        aborted {
            echo '''
============================================================
PIPELINE ABORTED
============================================================
The Jenkins build was manually aborted.
============================================================
'''
        }
    }
}