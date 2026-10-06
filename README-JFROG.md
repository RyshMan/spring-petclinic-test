# Spring PetClinic Jenkins and JFrog assessment

This document explains the infrastructure added to the upstream Spring
PetClinic project: how Docker is used, how Jenkins runs locally, how JFrog
Cloud supplies dependencies and stores the application image, and how the
self-hosted Artifactory bonus works.

The original Spring PetClinic documentation remains in [`README.md`](README.md).

## Architecture

```text
GitHub repository
       |
       v
Local Jenkins pipeline
       |
       +--> JFrog Cloud Maven virtual repository --> compile, test, package
       |
       +--> JFrog Cloud Docker virtual repository --> test and runtime images
       |
       +--> JFrog Cloud Docker local repository <-- push PetClinic image
       |
       +--> Run the image and check /actuator/health
       |
       +--> Optional: publish the JAR to self-hosted Artifactory
```

JFrog Cloud is the dependency source and Docker image registry required by the
assessment. The self-hosted instance is an additional publication target for
the bonus requirement.

## What Docker does

Docker is used in four parts of this solution.

### 1. Package PetClinic as a runnable image

The repository [`Dockerfile`](Dockerfile) receives the Java runtime image as a
build argument. Jenkins sets that argument to the Java image cached through the
JFrog Cloud Docker virtual repository.

The image:

- copies the executable Spring Boot JAR to `/app/petclinic.jar`;
- creates and runs as the unprivileged `petclinic` user;
- exposes application port `8080`;
- starts the application with `java -jar /app/petclinic.jar`.

The resulting image from the verified build is:

```text
talgat.jfrog.io/docker-local/petclinic:8f6f4b0d6ca5
```

### 2. Run integration-test dependencies

The Maven tests use Docker for MySQL, PostgreSQL, and Testcontainers. Jenkins
sets the Docker registry prefixes so these images are pulled through
`talgat.jfrog.io/docker-virtual` rather than directly from Docker Hub.

### 3. Smoke-test the packaged application

After pushing the image, Jenkins creates a temporary Docker network and starts
the exact image that was published. A curl container from the JFrog Docker
virtual repository calls:

```text
/actuator/health
```

The stage succeeds only when the response contains `"status":"UP"`. Jenkins
then removes the temporary container and network.

### 4. Run Jenkins and self-hosted Artifactory locally

Docker also runs the local Jenkins controller and the optional Artifactory OSS
stack. Named volumes keep Jenkins, Artifactory, and PostgreSQL data across
container restarts.

## Local Jenkins

The custom Jenkins image is defined in
[`ci/jenkins/Dockerfile`](ci/jenkins/Dockerfile). It uses the pinned Jenkins LTS
image `jenkins/jenkins:2.580.1-lts-jdk21` and installs the Docker CLI and Docker
Compose plugin.

Build it with:

```bash
docker build \
  -t petclinic-jenkins:2.580.1-jdk21 \
  -f ci/jenkins/Dockerfile \
  .
```

Run Jenkins locally:

```bash
docker run -d \
  --name jenkins \
  --restart=unless-stopped \
  -p 127.0.0.1:8080:8080 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  petclinic-jenkins:2.580.1-jdk21
```

Jenkins is available at <http://localhost:8080>.

The Docker socket lets this trusted local Jenkins instance build images and
start test containers on Docker Desktop. In a production environment, builds
should run on isolated Jenkins agents with controlled Docker access.

The Jenkins job is a **Pipeline script from SCM** job using:

- repository: `https://github.com/RyshMan/spring-petclinic-test.git`;
- branch: `*/jfrog-jenkins-pipeline`;
- script path: `Jenkinsfile`.

The [`Jenkinsfile`](Jenkinsfile) executes these stages:

1. Checkout the exact Git revision.
2. Validate the JFrog and repository parameters.
3. Compile the application.
4. Run unit and integration tests and publish JUnit results.
5. Package and archive the executable JAR.
6. Build the non-root Docker image.
7. Push the commit-tagged image to JFrog Cloud.
8. Start the image and run the health check.
9. Optionally publish the JAR to self-hosted Artifactory.

## JFrog Cloud SaaS

The JFrog Cloud environment is `https://talgat.jfrog.io`. It is used for all
application build dependencies and for the final Docker image.

The following repositories were created:

| Repository | Type | Purpose |
| --- | --- | --- |
| `maven-central-remote` | Maven remote | Proxy and cache Maven Central |
| `maven-virtual` | Maven virtual | Single Maven endpoint used by Jenkins |
| `dockerhub-remote` | Docker remote | Proxy and cache Docker Hub |
| `docker-virtual` | Docker virtual | Single endpoint for dependency images |
| `docker-local` | Docker local | Store the built PetClinic image |

Dependency routing is enforced in several places:

- `MVNW_REPOURL` resolves the Maven wrapper distribution through Artifactory.
- [`ci/settings.xml`](ci/settings.xml) uses `mirrorOf=*`, forcing Maven
  dependencies and plugins through `maven-virtual`.
- `TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX` routes Testcontainers images through
  `docker-virtual`.
- `DOCKER_REGISTRY_PREFIX` routes Docker Compose database images through
  `docker-virtual`.
- The Docker build receives the Java runtime image from `docker-virtual`.
- The smoke test receives its curl image from `docker-virtual`.
- The finished application image is pushed to `docker-local`.

Jenkins stores the Cloud username and scoped access token in a username/password
credential with ID `jfrog-cloud`. The token is injected only while a stage is
running, masked in logs, and never stored in Git or passed as a normal build
parameter.

The verified Jenkins build was build `#8`. It completed 81 tests with no
failures or skipped tests, pushed the image, and returned an `UP` health status.
The published image digest is:

```text
sha256:73f5ad7ad65b0136f8874fdc97d870c4c2c8f60ec2d10bf33a6a0ef56a1dec43
```

## Self-hosted JFrog Artifactory bonus

The self-hosted deployment is defined in
[`ci/artifactory/docker-compose.yml`](ci/artifactory/docker-compose.yml). It
contains:

- `artifactory-init`: a one-time container that creates persistent encryption
  keys with restricted permissions;
- `postgresql`: PostgreSQL 16.8 for Artifactory metadata;
- `artifactory`: Artifactory OSS 7.161.15;
- `artifactory_data` and `postgresql_data`: named volumes for persistent data.

Create the ignored local environment file and start the stack:

```bash
cp ci/artifactory/.env.example ci/artifactory/.env
# Replace the example password in ci/artifactory/.env.
docker compose -f ci/artifactory/docker-compose.yml up -d
```

Artifactory is available at <http://localhost:8082>. A clean first startup can
take several minutes while the PostgreSQL schema and platform services are
initialized. If the Router reaches its first-start timeout, restart only the
Artifactory container:

```bash
docker restart artifactory-local
```

The current local deployment was verified with all required JFrog services in
the `HEALTHY` state and an `OK` response from the Artifactory system ping.

Artifactory OSS provides the Generic repository `example-repo-local`. The
verified Jenkins JAR was uploaded to:

```text
example-repo-local/org/springframework/samples/spring-petclinic/build-8/
spring-petclinic-4.0.0-SNAPSHOT.jar
```

The stored JAR is 65,831,267 bytes and has SHA-256 checksum:

```text
8e58d1a452bbbf642f09fada2cd14463b6372efef491d454fdadffbcd17ac3c3
```

For Jenkins, create a username/password credential named
`jfrog-self-hosted`. Run the job with these parameters to exercise the bonus
stage:

| Parameter | Value |
| --- | --- |
| `PUBLISH_SELF_HOSTED` | `true` |
| `SELF_HOSTED_ARTIFACTORY_HOST` | `host.docker.internal:8082` |
| `SELF_HOSTED_REPOSITORY` | `example-repo-local` |
| `SELF_HOSTED_CREDENTIALS_ID` | `jfrog-self-hosted` |

The bonus stage uploads the packaged JAR and then performs a HEAD request to
verify that the artifact exists. Maven and Docker dependencies continue to use
JFrog Cloud, preserving the main assessment requirement.

## Run the Docker image

From JFrog Cloud:

```bash
docker login talgat.jfrog.io
docker pull talgat.jfrog.io/docker-local/petclinic:8f6f4b0d6ca5
docker run --rm -p 8080:8080 \
  talgat.jfrog.io/docker-local/petclinic:8f6f4b0d6ca5
```

From the attached portable archive:

```bash
gunzip -c petclinic-8f6f4b0d6ca5.tar.gz | docker load
docker run --rm -p 8080:8080 \
  talgat.jfrog.io/docker-local/petclinic:8f6f4b0d6ca5
```

The archive SHA-256 checksum is:

```text
2f332de07f3ae1ff244725cfa89db9be7958cdbd454d0cf7d8acb4e61d44ea0a
```

Open <http://localhost:8080> after starting the container. The application
health endpoint is <http://localhost:8080/actuator/health>.

## Secrets

- JFrog Cloud and self-hosted credentials are stored in Jenkins Credentials.
- The local PostgreSQL password is stored in ignored
  `ci/artifactory/.env`.
- Tokens, passwords, private keys, and Docker login files are not committed.
- Jenkins deletes its temporary Docker configuration after every build.
