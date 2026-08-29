#!/usr/bin/env bash
# Lekcja 28 - male funkcje pomocnicze wspoldzielone przez skrypty.
set -euo pipefail

# Git Bash na Windows zamienia argumenty wygladajace jak sciezki unixowe
# (np. ARN-y polityk) na sciezki Windows. To wylacza te konwersje.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

LESSON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$LESSON_DIR/evidence"
SECRETS_DIR="$LESSON_DIR/.secrets"
mkdir -p "$EVIDENCE_DIR" "$SECRETS_DIR"

# shellcheck source=../config.sh
source "$LESSON_DIR/config.sh"

# Kolory tylko wtedy, gdy piszemy na terminal.
if [ -t 1 ]; then
  C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_WARN=''; C_ERR=''; C_DIM=''; C_OFF=''
fi

info() { printf '%s\n' "$*"; }
ok()   { printf '%s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
skip() { printf '%s[skip]%s %s\n' "$C_DIM" "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[err]%s  %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

header() {
  printf '\n=== %s ===\n' "$*"
}

# aws_cli - wywolanie AWS CLI profilem podanym w AWS_PROFILE (jesli ustawiony).
aws_cli() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    aws --profile "$AWS_PROFILE" "$@"
  else
    aws "$@"
  fi
}

# capture <plik-dowodu> <opis> -- <polecenie...>
# Uruchamia polecenie, pokazuje wynik na ekranie i dopisuje go do pliku
# w evidence/, razem z trescia samego polecenia. Dzieki temu README moze
# cytowac prawdziwe wyniki, a nie wymyslone.
capture() {
  local file="$EVIDENCE_DIR/$1"; shift
  local desc="$1"; shift
  [ "${1:-}" = "--" ] && shift

  {
    printf '\n# %s\n' "$desc"
    printf '$ %s\n' "${*/#aws_cli/aws}"
  } | tee -a "$file"

  if "$@" 2>&1 | mask_secrets | tee -a "$file"; then
    return 0
  else
    return "${PIPESTATUS[0]}"
  fi
}

# mask_secrets - zaslania identyfikatory kluczy dostepu (AKIA... / ASIA...).
# Sam Access Key ID nie jest haslem, ale pliki z evidence/ trafiaja do repozytorium,
# a klucza AWS nie wklada sie do gita nawet w polowie.
mask_secrets() {
  sed -E 's/(AKIA|ASIA)[A-Z0-9]{8,}/\1************/g'
}

# start_evidence <plik> <tytul> - czysci plik i wpisuje naglowek z data.
start_evidence() {
  local file="$EVIDENCE_DIR/$1"
  {
    printf '# %s\n' "$2"
    printf '# region: %s\n' "$AWS_REGION"
  } > "$file"
}

# account_id - numer konta AWS, ustalany raz i zapamietywany.
account_id() {
  if [ -z "${_ACCOUNT_ID:-}" ]; then
    _ACCOUNT_ID="$(aws_cli sts get-caller-identity --query Account --output text)"
  fi
  printf '%s' "$_ACCOUNT_ID"
}

# iam_exists <typ> <nazwa> - czy zasob IAM juz istnieje (idempotencja skryptow).
iam_exists() {
  case "$1" in
    group) aws_cli iam get-group --group-name "$2" >/dev/null 2>&1 ;;
    user)  aws_cli iam get-user  --user-name  "$2" >/dev/null 2>&1 ;;
    policy) aws_cli iam get-policy --policy-arn "arn:aws:iam::$(account_id):policy/$2" >/dev/null 2>&1 ;;
    *) die "iam_exists: nieznany typ '$1'" ;;
  esac
}

# use_lesson_profile - przelacza skrypt na profil utworzony w 01-iam-structure.sh.
# Cel lekcji: po utworzeniu wlasnego uzytkownika IAM nie pracujemy juz rootem.
# Jesli profil nie istnieje, zostajemy przy domyslnych danych logowania.
use_lesson_profile() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    info "Uzywam profilu z otoczenia: $AWS_PROFILE"
  elif aws configure list-profiles 2>/dev/null | grep -qx "$CLI_PROFILE"; then
    export AWS_PROFILE="$CLI_PROFILE"
    info "Uzywam profilu $CLI_PROFILE ($MY_IAM_USER)"
  else
    warn "Profil '$CLI_PROFILE' nie istnieje - uruchom najpierw 01-iam-structure.sh."
    warn "Na razie uzywam domyslnych danych logowania."
  fi
}

# native_path - sciezka w formacie zrozumialym dla uruchamianego programu.
# aws.exe na Windows nie rozumie sciezek Git Basha ("/c/..."), wiec przed
# podaniem sciezki lokalnej do CLI zamieniamy ja na "C:\...".
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}
