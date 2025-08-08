pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'your-registry.amazonaws.com'
        AWS_REGION = 'us-west-2'
        IMAGE_TAG = "${BUILD_NUMBER}"
        FRONTEND_IMAGE = "${DOCKER_REGISTRY}/frontend-app:${IMAGE_TAG}"
        NODE_VERSION = '18'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Setup Node Environment') {
            steps {
                script {
                    dir('frontend') {
                        sh '''
                            # Use nvm to manage Node.js versions
                            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
                            export NVM_DIR="$HOME/.nvm"
                            [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
                            nvm install ${NODE_VERSION}
                            nvm use ${NODE_VERSION}
                            
                            # Install dependencies
                            npm ci
                        '''
                    }
                }
            }
        }
        
        stage('Lint and Type Check') {
            steps {
                script {
                    dir('frontend') {
                        sh '''
                            export NVM_DIR="$HOME/.nvm"
                            [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
                            nvm use ${NODE_VERSION}
                            
                            npm run lint
                            npx tsc --noEmit
                        '''
                    }
                }
            }
        }
        
        stage('Run Frontend Tests') {
            steps {
                script {
                    dir('frontend') {
                        sh '''
                            export NVM_DIR="$HOME/.nvm"
                            [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
                            nvm use ${NODE_VERSION}
                            
                            npm run test:ci
                        '''
                    }
                }
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'frontend/coverage/junit.xml'
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'frontend/coverage/lcov-report',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }
        
        stage('Security Audit') {
            steps {
                script {
                    dir('frontend') {
                        sh '''
                            export NVM_DIR="$HOME/.nvm"
                            [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
                            nvm use ${NODE_VERSION}
                            
                            npm audit --audit-level moderate
                        '''
                    }
                }
            }
        }
        
        stage('Build Application') {
            steps {
                script {
                    dir('frontend') {
                        sh '''
                            export NVM_DIR="$HOME/.nvm"
                            [ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"
                            nvm use ${NODE_VERSION}
                            
                            npm run build
                        '''
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    dir('frontend') {
                        sh "docker build -t ${FRONTEND_IMAGE} ."
                    }
                }
            }
        }
        
        stage('Test Docker Image') {
            steps {
                script {
                    sh '''
                        # Run container in background
                        docker run -d --name frontend-test -p 3001:3000 ${FRONTEND_IMAGE}
                        sleep 15
                        
                        # Test health endpoint
                        curl -f http://localhost:3001 || exit 1
                        
                        # Test if the page loads
                        response=$(curl -s http://localhost:3001)
                        echo "Response length: ${#response}"
                        
                        # Cleanup
                        docker stop frontend-test
                        docker rm frontend-test
                    '''
                }
            }
        }
        
        stage('Push to Registry') {
            when {
                allOf {
                    branch 'main'
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                script {
                    sh '''
                        # Login to AWS ECR
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${DOCKER_REGISTRY}
                        
                        # Push image
                        docker push ${FRONTEND_IMAGE}
                        
                        # Tag as latest
                        docker tag ${FRONTEND_IMAGE} ${DOCKER_REGISTRY}/frontend-app:latest
                        docker push ${DOCKER_REGISTRY}/frontend-app:latest
                    '''
                }
            }
        }
        
        stage('Trigger Deployment') {
            when {
                allOf {
                    branch 'main'
                    expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
                }
            }
            steps {
                script {
                    // Trigger OpenTofu deployment
                    build job: 'opentofu-deployment', parameters: [
                        string(name: 'FRONTEND_IMAGE_TAG', value: "${IMAGE_TAG}"),
                        string(name: 'ENVIRONMENT', value: 'production')
                    ]
                }
            }
        }
    }
    
    post {
        always {
            // Cleanup
            sh '''
                docker rmi ${FRONTEND_IMAGE} || true
                docker system prune -f || true
            '''
        }
        failure {
            emailext (
                subject: "Pipeline Failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                body: "The frontend pipeline has failed. Please check the console output.",
                to: "${env.CHANGE_AUTHOR_EMAIL}"
            )
        }
        success {
            echo 'Frontend pipeline completed successfully!'
        }
    }
}
