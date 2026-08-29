# Kontroler Jenkins dla lekcji 27.
# Zawiera pluginy potrzebne do agentow SSH, chmury Docker i konfiguracji jako kod (JCasC).
FROM jenkins/jenkins:lts-jdk21

USER root
# klient docker-a nie jest wymagany przez pluginy, ale ulatwia diagnostyke
# polaczenia z demonem (docker -H ... info) z wnetrza kontenera kontrolera
RUN apt-get update \
    && apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/*
USER jenkins

RUN jenkins-plugin-cli --plugins \
    configuration-as-code \
    job-dsl \
    workflow-aggregator \
    git \
    ssh-slaves \
    docker-plugin \
    credentials-binding \
    pipeline-utility-steps \
    timestamper \
    junit

# Konfiguracja Jenkinsa jest podawana w calosci przez JCasC,
# wiec kreator pierwszego uruchomienia jest wylaczony.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_config/jenkins.yaml
