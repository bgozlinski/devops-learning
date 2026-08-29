#!/usr/bin/env bash
# Lekcja 27 - zadanie domowe 1, wariant z prawdziwa maszyna wirtualna.
#
# Skrypt przygotowuje swiezo zainstalowane Ubuntu (VirtualBox / VMware / VPS)
# do roli agenta Jenkinsa podlaczanego po SSH. Odpowiada temu, co lab robi
# w pliku jenkins/agent.Dockerfile.
#
#   sudo bash setup-agent-vm.sh
#
set -euo pipefail

AGENT_USER="${AGENT_USER:-jenkins}"
AGENT_PASSWORD="${AGENT_PASSWORD:-jenkins123}"
AGENT_HOME="/home/${AGENT_USER}"
REMOTE_FS="${AGENT_HOME}/agent"

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom skrypt jako root (sudo bash $0)." >&2
    exit 1
fi

echo "==> Instalacja pakietow (SSH + JRE zgodne z kontrolerem)"
apt-get update
apt-get install -y --no-install-recommends openssh-server openjdk-21-jre-headless sudo procps
systemctl enable --now ssh

echo "==> Uzytkownik ${AGENT_USER}"
if ! id "${AGENT_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${AGENT_USER}"
fi
echo "${AGENT_USER}:${AGENT_PASSWORD}" | chpasswd
usermod -aG sudo "${AGENT_USER}"

echo "==> Katalog roboczy agenta: ${REMOTE_FS}"
mkdir -p "${REMOTE_FS}"
chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}"

# Wariant produkcyjny: logowanie kluczem zamiast haslem.
# Skopiuj klucz publiczny kontrolera i wylacz PasswordAuthentication:
#
#   mkdir -p ${AGENT_HOME}/.ssh && chmod 700 ${AGENT_HOME}/.ssh
#   cat controller_key.pub >> ${AGENT_HOME}/.ssh/authorized_keys
#   chmod 600 ${AGENT_HOME}/.ssh/authorized_keys
#   chown -R ${AGENT_USER}:${AGENT_USER} ${AGENT_HOME}/.ssh
#   sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
#   systemctl restart ssh

echo
echo "Maszyna gotowa. W Jenkinsie dodaj wezel:"
echo "  Manage Jenkins -> Nodes -> New Node -> Permanent Agent"
echo "  Name                : linux-worker-01"
echo "  Labels              : linux-worker-01 linux ubuntu"
echo "  Remote root dir     : ${REMOTE_FS}"
echo "  Launch method       : Launch agents via SSH"
echo "  Host                : $(hostname -I | awk '{print $1}')"
echo "  Credentials         : ${AGENT_USER} / <haslo>"
echo "  Node properties     : Environment variables -> NODE_ENV=production"
echo
java -version
