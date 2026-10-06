FROM jenkins/jenkins:2.580.1-lts-jdk21

# Local-only controller: root is required to use Docker Desktop's mounted socket.
# hadolint ignore=DL3002
USER root

# Track the security-supported Docker CLI supplied by the pinned image's Debian release.
# hadolint ignore=DL3008
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends docker-cli \
	&& rm -rf /var/lib/apt/lists/*

# Local assessment only: root is required for the Docker Desktop socket mount.
# Production Jenkins builds should run on isolated, least-privilege agents.
