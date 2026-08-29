# Zadanie domowe 2 - obraz agenta uruchamianego na zadanie przez chmure Docker.
#
# Baza: jenkins/inbound-agent - agent sam laczy sie do kontrolera (JNLP),
# wiec kontroler nie musi otwierac polaczenia do kontenera. To wazne, bo
# kontroler tez dziala w kontenerze: przy metodzie SSH plugin publikuje port 22
# kontenera na losowym porcie hosta i probuje sie polaczyc na "localhost",
# ktory z wnetrza kontenera kontrolera jest jego wlasnym localhostem.
#
# git i python3 sa dodane po to, zeby agent mogl budowac projekty
# z tego repozytorium (jak w lekcjach 25-26).
FROM jenkins/inbound-agent:jdk21

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends git python3 procps \
    && rm -rf /var/lib/apt/lists/*
USER jenkins
