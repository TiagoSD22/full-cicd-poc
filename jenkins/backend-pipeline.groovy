pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'your-registry.amazonaws.com'
        AWS_REGION = 'us-west-2'
        IMAGE_TAG = "${BUILD_NUMBER}"
        BACKEND_IMAGE = "${DOCKER_REGISTRY}/backend-api:${IMAGE_TAG}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Setup Python Environment') {
            steps {
                script {
                    dir('backend') {
                        sh '''
                            python3 -m venv venv
                            . venv/bin/activate
                            pip install --upgrade pip
                            pip install -r requirements.txt
                        '''
                    }
                }
            }
        }
        
        stage('Run Backend Tests') {
            steps {
                script {
                    dir('backend') {
                        sh '''
                            . venv/bin/activate
                            pytest test_app.py -v --junitxml=test-results.xml
                        '''
                    }
                }
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'backend/test-results.xml'
                }
            }
        }
        
        stage('Security Scan') {
            steps {
                script {
                    dir('backend') {
                        sh '''
                            . venv/bin/activate
                            pip install safety bandit
                            safety check --json --output safety-report.json || true
                            bandit -r . -f json -o bandit-report.json || true
                        '''
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    dir('backend') {
                        sh "docker build -t ${BACKEND_IMAGE} ."
                    }
                }
            }
        }
        
        stage('Test Docker Image') {
            steps {
                script {
                    sh '''
                        # Run container in background
                        docker run -d --name backend-test -p 5001:5000 ${BACKEND_IMAGE}
                        sleep 10
                        
                        # Test health endpoint
                        curl -f http://localhost:5001/health || exit 1
                        
                        # Test API endpoint
                        response=$(curl -s http://localhost:5001/api/hello)
                        echo "Response: $response"
                        
                        # Cleanup
                        docker stop backend-test
                        docker rm backend-test
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
                        docker push ${BACKEND_IMAGE}
                        
                        # Tag as latest
                        docker tag ${BACKEND_IMAGE} ${DOCKER_REGISTRY}/backend-api:latest
                        docker push ${DOCKER_REGISTRY}/backend-api:latest
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
                        string(name: 'BACKEND_IMAGE_TAG', value: "${IMAGE_TAG}"),
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
                docker rmi ${BACKEND_IMAGE} || true
                docker system prune -f || true
            '''
        }
        failure {
            emailext (
                subject: "Pipeline Failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                body: "The backend pipeline has failed. Please check the console output.",
                to: "${env.CHANGE_AUTHOR_EMAIL}"
            )
        }
        success {
            echo 'Backend pipeline completed successfully!'
        }
    }
}
