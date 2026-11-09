# ---------- Stage 1: Build ----------
FROM gradle:9.8.2-jdk25-alpine AS build
WORKDIR /app

COPY settings.gradle build.gradle ./
RUN gradle dependencies --no-daemon

COPY src ./src
RUN gradle bootJar --no-daemon -x test \
    && cp build/libs/*.jar app.jar

# ---------- Stage 2: Runtime ----------
FROM eclipse-temurin:25-jre-alpine
WORKDIR /app

RUN addgroup -S -g 1001 spring && adduser -S -u 1001 -G spring spring
COPY --from=build --chown=1001:1001 /app/app.jar app.jar

USER 1001:1001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]