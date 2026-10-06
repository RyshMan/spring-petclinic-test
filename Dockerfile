# RUNTIME_IMAGE is required so CI must name the JFrog-hosted image explicitly.
ARG RUNTIME_IMAGE
FROM ${RUNTIME_IMAGE}

RUN groupadd --system petclinic \
	&& useradd --system --gid petclinic --create-home --home-dir /app petclinic

WORKDIR /app
COPY --chown=petclinic:petclinic target/spring-petclinic-*.jar /app/petclinic.jar

USER petclinic:petclinic
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
