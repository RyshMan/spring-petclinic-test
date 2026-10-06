pipeline {
	agent any

	options {
		disableConcurrentBuilds()
		skipDefaultCheckout(true)
		timeout(time: 30, unit: 'MINUTES')
	}

	parameters {
		string(name: 'JFROG_BASE_URL', defaultValue: 'https://talgat.jfrog.io', description: 'JFrog base URL, without a trailing slash')
		string(name: 'MAVEN_REPOSITORY', defaultValue: 'maven-virtual', description: 'Maven virtual repository key')
		string(name: 'DOCKER_REGISTRY', defaultValue: 'talgat.jfrog.io', description: 'Docker registry hostname, without https://')
		string(name: 'DOCKER_REMOTE_REPOSITORY', defaultValue: 'docker-virtual', description: 'Docker virtual/remote repository used for dependency images')
		string(name: 'DOCKER_LOCAL_REPOSITORY', defaultValue: 'docker-local', description: 'Docker local repository used for the Petclinic image')
		string(name: 'JFROG_CREDENTIALS_ID', defaultValue: 'jfrog-cloud', description: 'Jenkins username/password credential ID')
	}

	environment {
		JFROG_BASE_URL = "${params.JFROG_BASE_URL}"
		MAVEN_REPOSITORY = "${params.MAVEN_REPOSITORY}"
		DOCKER_REGISTRY = "${params.DOCKER_REGISTRY}"
		DOCKER_REMOTE_REPOSITORY = "${params.DOCKER_REMOTE_REPOSITORY}"
		DOCKER_LOCAL_REPOSITORY = "${params.DOCKER_LOCAL_REPOSITORY}"
	}

	stages {
		stage('Checkout') {
			steps {
				deleteDir()
				checkout scm
				script {
					env.IMAGE_TAG = sh(
						script: 'git rev-parse --short=12 HEAD',
						returnStdout: true
					).trim()
				}
			}
		}

		stage('Validate configuration') {
			steps {
				script {
					if (!params.JFROG_BASE_URL.startsWith('https://') || params.JFROG_BASE_URL.contains('YOUR_SERVER')) {
						error('Set JFROG_BASE_URL to your JFrog Cloud URL')
					}
					if (!params.DOCKER_REGISTRY?.trim() || params.DOCKER_REGISTRY.contains('://') || params.DOCKER_REGISTRY.contains('YOUR_SERVER')) {
						error('Set DOCKER_REGISTRY to the JFrog hostname without https://')
					}
					if (!params.MAVEN_REPOSITORY?.trim() || !params.DOCKER_REMOTE_REPOSITORY?.trim() || !params.DOCKER_LOCAL_REPOSITORY?.trim()) {
						error('Repository parameters must not be empty')
					}
				}
				sh 'docker version'
			}
		}

		stage('Compile') {
			steps {
				withCredentials([usernamePassword(
					credentialsId: params.JFROG_CREDENTIALS_ID,
					usernameVariable: 'JFROG_USER',
					passwordVariable: 'JFROG_TOKEN'
				)]) {
					sh '''
						set -eu
						export MAVEN_USER_HOME="$WORKSPACE@tmp/.m2"
						export MVNW_REPOURL="$JFROG_BASE_URL/artifactory/$MAVEN_REPOSITORY"
						export MVNW_USERNAME="$JFROG_USER"
						export MVNW_PASSWORD="$JFROG_TOKEN"
						./mvnw -B -ntp -s ci/settings.xml clean compile
					'''
				}
			}
		}

		stage('Test') {
			steps {
				withCredentials([usernamePassword(
					credentialsId: params.JFROG_CREDENTIALS_ID,
					usernameVariable: 'JFROG_USER',
					passwordVariable: 'JFROG_TOKEN'
				)]) {
					sh '''
						set -eu
						export MAVEN_USER_HOME="$WORKSPACE@tmp/.m2"
						export MVNW_REPOURL="$JFROG_BASE_URL/artifactory/$MAVEN_REPOSITORY"
						export MVNW_USERNAME="$JFROG_USER"
						export MVNW_PASSWORD="$JFROG_TOKEN"
						export DOCKER_CONFIG="$WORKSPACE/.docker"
						export DOCKER_REGISTRY_PREFIX="$DOCKER_REGISTRY/$DOCKER_REMOTE_REPOSITORY/"
						export POSTGRES_URL='jdbc:postgresql://host.docker.internal:5432/petclinic'
						export SPRING_DOCKER_COMPOSE_HOST='host.docker.internal'
						export TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX="$DOCKER_REGISTRY/$DOCKER_REMOTE_REPOSITORY/"
						export TESTCONTAINERS_HOST_OVERRIDE='host.docker.internal'

						mkdir -p "$DOCKER_CONFIG"
						set +x
						printf '%s' "$JFROG_TOKEN" | docker login "$DOCKER_REGISTRY" --username "$JFROG_USER" --password-stdin
						set -x

						./mvnw -B -ntp -s ci/settings.xml test

						report='target/surefire-reports/TEST-org.springframework.samples.petclinic.MySqlIntegrationTests.xml'
						test -s "$report"
						if grep -q '<skipped' "$report"; then
							echo 'MySqlIntegrationTests was skipped; check Jenkins Docker access'
							exit 1
						fi
					'''
				}
			}
			post {
				always {
					junit allowEmptyResults: false, testResults: 'target/surefire-reports/*.xml'
				}
			}
		}

		stage('Package') {
			steps {
				withCredentials([usernamePassword(
					credentialsId: params.JFROG_CREDENTIALS_ID,
					usernameVariable: 'JFROG_USER',
					passwordVariable: 'JFROG_TOKEN'
				)]) {
					sh '''
						set -eu
						export MAVEN_USER_HOME="$WORKSPACE@tmp/.m2"
						export MVNW_REPOURL="$JFROG_BASE_URL/artifactory/$MAVEN_REPOSITORY"
						export MVNW_USERNAME="$JFROG_USER"
						export MVNW_PASSWORD="$JFROG_TOKEN"
						./mvnw -B -ntp -s ci/settings.xml -DskipTests package
					'''
				}
				archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
			}
		}

		stage('Build image') {
			steps {
				script {
					env.IMAGE_NAME = "${env.DOCKER_REGISTRY}/${env.DOCKER_LOCAL_REPOSITORY}/petclinic:${env.IMAGE_TAG}"
					env.RUNTIME_IMAGE = "${env.DOCKER_REGISTRY}/${env.DOCKER_REMOTE_REPOSITORY}/eclipse-temurin:17-jre"
					env.CURL_IMAGE = "${env.DOCKER_REGISTRY}/${env.DOCKER_REMOTE_REPOSITORY}/curlimages/curl:8.16.0"
				}
				sh '''
					set -eu
					export DOCKER_CONFIG="$WORKSPACE/.docker"
					docker build --pull \
						--build-arg "RUNTIME_IMAGE=$RUNTIME_IMAGE" \
						--tag "$IMAGE_NAME" \
						.
				'''
			}
		}

		stage('Push image') {
			steps {
				withCredentials([usernamePassword(
					credentialsId: params.JFROG_CREDENTIALS_ID,
					usernameVariable: 'JFROG_USER',
					passwordVariable: 'JFROG_TOKEN'
				)]) {
					sh '''
						set -eu
						export DOCKER_CONFIG="$WORKSPACE/.docker"
						set +x
						printf '%s' "$JFROG_TOKEN" | docker login "$DOCKER_REGISTRY" --username "$JFROG_USER" --password-stdin
						set -x
						docker push "$IMAGE_NAME"
					'''
				}
			}
		}

		stage('Smoke test') {
			steps {
				sh '''
					set -eu
					export DOCKER_CONFIG="$WORKSPACE/.docker"
					container_name="petclinic-smoke-$IMAGE_TAG"
					network_name="petclinic-smoke-$IMAGE_TAG"
					health_scheme='http'

					cleanup() {
						docker rm -f "$container_name" >/dev/null 2>&1 || true
						docker network rm "$network_name" >/dev/null 2>&1 || true
					}
					trap cleanup EXIT
					cleanup

					docker network create "$network_name" >/dev/null
					docker run -d --name "$container_name" --network "$network_name" "$IMAGE_NAME" >/dev/null

					ready=0
					for attempt in $(seq 1 45); do
						if docker run --rm --network "$network_name" "$CURL_IMAGE" \
							-fsS "$health_scheme://$container_name:8080/actuator/health" \
							| tee /tmp/petclinic-health.json \
							| grep -q '"status":"UP"'; then
							ready=1
							break
						fi
						sleep 2
					done

					if [ "$ready" -ne 1 ]; then
						docker logs "$container_name"
						exit 1
					fi

					cat /tmp/petclinic-health.json
				'''
			}
		}
	}

	post {
		always {
			sh '''
				set +e
				export DOCKER_CONFIG="$WORKSPACE/.docker"
				docker logout "$DOCKER_REGISTRY" >/dev/null 2>&1
				rm -rf "$DOCKER_CONFIG"
			'''
		}
		cleanup {
			deleteDir()
		}
	}
}
