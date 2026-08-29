# Zadanie domowe 1 - odpowiednik maszyny wirtualnej z agentem Jenkinsa.
# Ten kontener zastepuje osobna VM (VirtualBox / VMware / VPS) z PDF-a:
# Ubuntu 22.04 + serwer SSH + JRE w wersji zgodnej z kontrolerem + uzytkownik jenkins.
# Te same kroki dla prawdziwej maszyny sa w ../scripts/setup-agent-vm.sh
FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openssh-server \
        openjdk-21-jre-headless \
        sudo \
        ca-certificates \
        procps \
    && rm -rf /var/lib/apt/lists/*

# Uzytkownik, na ktorym kontroler bedzie uruchamial agenta (jak w PDF-ie).
RUN useradd -m -s /bin/bash jenkins \
    && echo 'jenkins:jenkins123' | chpasswd \
    && usermod -aG sudo jenkins \
    && mkdir -p /home/jenkins/agent \
    && chown -R jenkins:jenkins /home/jenkins

# Logowanie haslem - w labie upraszcza konfiguracje credentiali.
# Na produkcji uzywa sie kluczy SSH (patrz sekcja "Security" w README).
RUN mkdir -p /run/sshd \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
