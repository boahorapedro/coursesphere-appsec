FROM eclipse-temurin:21-jre AS jre

FROM node:20-bookworm-slim
COPY --from=jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="/opt/java/openjdk/bin:${PATH}"
RUN npm install -g firebase-tools@15.34.1
WORKDIR /srv
COPY firebase.json database.rules.json ./
EXPOSE 9099 9000
CMD ["firebase", "emulators:start", "--only", "auth,database", "--project", "demo-coursesphere"]