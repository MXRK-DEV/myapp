pipeline {
    agent any

    environment {
        AWS_REGION       = 'us-east-1'
        ECR_REPOSITORY   = 'myapp'
        ECS_CLUSTER      = 'myapp-cluster'
        ECS_SERVICE_STG  = 'myapp-staging'
        ECS_SERVICE_PRD  = 'myapp-production'
        CONTAINER_NAME   = 'myapp'
        IMAGE_TAG        = "${env.GIT_COMMIT}"
        ECR_REGISTRY     = credentials('ecr-registry-url') // e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com
    }

    options {
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install & Test') {
            steps {
                sh 'npm ci'
                sh 'npm run lint'
                sh 'npm test -- --ci'
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'test-results/**/*.xml'
                    publishHTML target: [
                        reportDir: 'coverage', reportFiles: 'index.html', reportName: 'Coverage Report'
                    ]
                }
            }
        }

        stage('Security Audit') {
            steps {
                sh 'npm audit --audit-level=high || true'
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    docker.build("${ECR_REPOSITORY}:${IMAGE_TAG}")
                }
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-creds'
                ]]) {
                    sh '''
                        aws ecr get-login-password --region $AWS_REGION | \
                          docker login --username AWS --password-stdin $ECR_REGISTRY
                        docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} $ECR_REGISTRY/${ECR_REPOSITORY}:${IMAGE_TAG}
                        docker push $ECR_REGISTRY/${ECR_REPOSITORY}:${IMAGE_TAG}
                    '''
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-creds'
                ]]) {
                    sh '''
                        aws ecs describe-task-definition --task-definition myapp-staging \
                          --query taskDefinition > task-def.json
                        ./scripts/update-task-def.sh task-def.json $ECR_REGISTRY/${ECR_REPOSITORY}:${IMAGE_TAG} ${CONTAINER_NAME} > new-task-def.json
                        aws ecs register-task-definition --cli-input-json file://new-task-def.json
                        aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE_STG \
                          --task-definition myapp-staging --force-new-deployment
                        aws ecs wait services-stable --cluster $ECS_CLUSTER --services $ECS_SERVICE_STG
                    '''
                }
            }
            post {
                success {
                    slackSend color: 'good', message: "Staging deploy succeeded — build ${env.BUILD_NUMBER} (${env.GIT_COMMIT})"
                }
                failure {
                    slackSend color: 'danger', message: "Staging deploy FAILED — build ${env.BUILD_NUMBER}"
                }
            }
        }

        stage('Approve Production?') {
            steps {
                input message: 'Deploy to production?',
                      ok: 'Deploy Now',
                      submitter: 'devops-team'
            }
        }

        stage('Deploy to Production') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-jenkins-creds'
                ]]) {
                    sh '''
                        aws ecs describe-task-definition --task-definition myapp-production \
                          --query taskDefinition > task-def-prod.json
                        ./scripts/update-task-def.sh task-def-prod.json $ECR_REGISTRY/${ECR_REPOSITORY}:${IMAGE_TAG} ${CONTAINER_NAME} > new-task-def-prod.json
                        aws ecs register-task-definition --cli-input-json file://new-task-def-prod.json
                        aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE_PRD \
                          --task-definition myapp-production --force-new-deployment
                        aws ecs wait services-stable --cluster $ECS_CLUSTER --services $ECS_SERVICE_PRD
                    '''
                }
            }
        }
    }

    post {
        success {
            slackSend color: 'good', message: ":white_check_mark: PRODUCTION deploy succeeded — build ${env.BUILD_NUMBER} (${env.GIT_COMMIT})"
            emailext subject: "Deploy success: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                     body: "Production deployment succeeded for commit ${env.GIT_COMMIT}.",
                     to: 'devops-team@example.com'
        }
        failure {
            slackSend color: 'danger', message: ":rotating_light: PRODUCTION deploy FAILED — build ${env.BUILD_NUMBER}"
            emailext subject: "DEPLOY FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                     body: "Pipeline failed at build ${env.BUILD_NUMBER}. Check Jenkins logs immediately.",
                     to: 'devops-team@example.com'
        }
    }
}
