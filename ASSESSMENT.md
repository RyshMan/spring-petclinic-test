# Jenkins and JFrog assessment

This repository builds Spring Petclinic with Jenkins and routes application build
dependencies through JFrog Artifactory Cloud.

## Pipeline flow

1. Checkout the exact Git revision.
2. Compile with Maven.
3. Run the unit and MySQL Testcontainers tests.
4. Package the executable Spring Boot JAR.
5. Build a non-root runtime image.
6. Push the commit-tagged image to Artifactory.
7. Start the published image and verify the Actuator health endpoint.

The Maven wrapper distribution, Maven dependencies and plugins, the Testcontainers
images, the Java runtime base image, and the smoke-test image all resolve through
Artifactory.

## JFrog Cloud setup

Create these repositories in the JFrog UI. The names can differ, but they must
match the Jenkins parameters:

| Repository | Type | Upstream or purpose |
| --- | --- | --- |
| `maven-central-remote` | Maven remote | `https://repo.maven.apache.org/maven2` |
| `maven-virtual` | Maven virtual | Include `maven-central-remote` |
| `dockerhub-remote` | Docker remote | Docker Hub |
| `docker-virtual` | Docker virtual | Include `dockerhub-remote` |
| `docker-local` | Docker local | Store the Petclinic image |

Create a scoped access token for Jenkins. It needs read access to the Maven and
Docker remote/virtual repositories and deploy access to `docker-local`.

In Jenkins, open **Manage Jenkins → Credentials → System → Global credentials**.
Add a **Username with password** credential:

- ID: `jfrog-cloud`
- Username: your JFrog username
- Password: the scoped JFrog access token

Do not put the token in this repository or in pipeline parameters.

## Give local Jenkins Docker access

The official Jenkins image does not include the Docker client. Build the local
assessment image from this repository:

```bash
docker build \
  -t petclinic-jenkins:2.580.1-jdk21 \
  -f ci/jenkins/Dockerfile \
  .
```

Recreate the existing local Jenkins container while preserving its named volume:

```bash
docker stop jenkins
docker rm jenkins

docker run -d \
  --name jenkins \
  --restart=unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  petclinic-jenkins:2.580.1-jdk21
```

This setup intentionally gives a local Jenkins controller access to the Docker
daemon and is suitable only for a trusted interview project on a development
machine. A production installation should run builds on isolated agents with
separate credentials and controlled Docker access.

## Create the Jenkins job

1. Select **New Item** and create a **Pipeline** named `spring-petclinic`.
2. Under **Pipeline**, choose **Pipeline script from SCM**.
3. Select **Git** and enter this fork's clone URL.
4. Set the branch specifier to `*/jfrog-jenkins-pipeline` while developing,
   or `*/main` after merging.
5. Keep the script path as `Jenkinsfile` and save.
6. Select **Build with Parameters** and enter:

| Parameter | Example |
| --- | --- |
| `JFROG_BASE_URL` | `https://talgat.jfrog.io` |
| `MAVEN_REPOSITORY` | `maven-virtual` |
| `DOCKER_REGISTRY` | `talgat.jfrog.io` |
| `DOCKER_REMOTE_REPOSITORY` | `docker-virtual` |
| `DOCKER_LOCAL_REPOSITORY` | `docker-local` |
| `JFROG_CREDENTIALS_ID` | `jfrog-cloud` |

Do not include `https://` in `DOCKER_REGISTRY`. Do not include a trailing slash
in `JFROG_BASE_URL`.

## Local verification

The same Maven path can be tested outside Jenkins without writing a token to
disk:

```bash
export JFROG_BASE_URL='https://talgat.jfrog.io'
export MAVEN_REPOSITORY='maven-virtual'
export JFROG_USER='your-user'
read -s JFROG_TOKEN
export JFROG_TOKEN
export MVNW_USERNAME="$JFROG_USER"
export MVNW_PASSWORD="$JFROG_TOKEN"
export MVNW_REPOURL="$JFROG_BASE_URL/artifactory/$MAVEN_REPOSITORY"
export MAVEN_USER_HOME="$PWD/.m2"

./mvnw -B -ntp -s ci/settings.xml clean test
```

Unset the credentials after the test:

```bash
unset JFROG_TOKEN MVNW_PASSWORD
```

## Evidence to show in the interview

- A successful Jenkins stage view with compile, test, package, image push, and
  smoke-test stages.
- Published JUnit results, including `MySqlIntegrationTests` with no skipped
  tests.
- Artifactory's Maven remote cache populated by the build.
- The commit-tagged `petclinic` image in `docker-local`.
- The smoke-test log showing `{"status":"UP"}`.
- A failed-test demonstration showing that image build and push do not execute.

## Self-hosted bonus

Deploy a self-hosted Artifactory trial with persistent storage using JFrog's
supported Docker Compose installer. Create a local Docker repository there and
add a second publish stage or a parameterized registry target. Keep the required
dependency resolution pointed at JFrog Cloud so the base requirement remains
easy to demonstrate.
