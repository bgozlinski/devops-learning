#!/usr/bin/env bash
# Lekcja 28, zadanie domowe 1 - struktura organizacyjna w IAM.
#
#   3 grupy  -> lesson28-admins / lesson28-developers / lesson28-readonly
#   3 uzytkownicy -> admin.user / dev.user / readonly.user
#   1 uzytkownik dla mnie -> $MY_IAM_USER + klucze + profil AWS CLI
#
# Uprawnienia nadajemy grupom, nie uzytkownikom - to podstawowa dobra praktyka
# IAM: uzytkownik dostaje uprawnienia przez czlonkostwo, wiec zmiana roli to
# przepiecie miedzy grupami, a nie edycja polityk przy koncie.
#
# Skrypt jest idempotentny - kazde uruchomienie tylko dopelnia to, czego brakuje.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EV=01-iam.txt
start_evidence "$EV" "Zadanie domowe 1 - struktura IAM"

ACCOUNT="$(account_id)"
TAGS="Key=Environment,Value=Learning Key=Lesson,Value=28"

# ---------------------------------------------------------------------------
# 1. Wlasna polityka dla developerow.
# ---------------------------------------------------------------------------
header "Polityka $DEVELOPER_POLICY_NAME"
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${DEVELOPER_POLICY_NAME}"

if iam_exists policy "$DEVELOPER_POLICY_NAME"; then
  skip "polityka $DEVELOPER_POLICY_NAME juz istnieje"
else
  # Dokument podajemy trescia, a nie przez file:// - Git Bash na Windows
  # potrafi przerobic sciezke w file:// na sciezke Windows i CLI jej nie znajduje.
  aws_cli iam create-policy \
    --policy-name "$DEVELOPER_POLICY_NAME" \
    --description "Lekcja 28 - developer: odczyt EC2, pelny dostep do bucketow lesson28-*, wymuszone MFA" \
    --policy-document "$(cat "$LESSON_DIR/policies/developer-policy.json")" \
    --tags $TAGS >/dev/null
  ok "utworzona polityka $POLICY_ARN"
fi

# ---------------------------------------------------------------------------
# 2. Grupy i przypisane do nich polityki.
# ---------------------------------------------------------------------------
header "Grupy"

# nazwa_grupy|arn_polityki|opis
IAM_GROUPS=(
  "$GROUP_ADMINS|arn:aws:iam::aws:policy/AdministratorAccess|pelne uprawnienia administracyjne"
  "$GROUP_DEVELOPERS|$POLICY_ARN|wlasna polityka - EC2 read-only + S3 lesson28-*"
  "$GROUP_READONLY|arn:aws:iam::aws:policy/ReadOnlyAccess|podglad calego konta, zero zmian"
)

for entry in "${IAM_GROUPS[@]}"; do
  IFS='|' read -r group arn desc <<< "$entry"

  if iam_exists group "$group"; then
    skip "grupa $group juz istnieje"
  else
    aws_cli iam create-group --group-name "$group" >/dev/null
    ok "utworzona grupa $group ($desc)"
  fi

  if aws_cli iam list-attached-group-policies --group-name "$group" \
       --query 'AttachedPolicies[].PolicyArn' --output text | grep -qF "$arn"; then
    skip "  polityka juz podpieta do $group"
  else
    aws_cli iam attach-group-policy --group-name "$group" --policy-arn "$arn"
    ok "  podpieta polityka $(basename "$arn") do $group"
  fi
done

# ---------------------------------------------------------------------------
# 3. Uzytkownicy rol.
# ---------------------------------------------------------------------------
header "Uzytkownicy"

IAM_USERS=(
  "$USER_ADMIN|$GROUP_ADMINS"
  "$USER_DEV|$GROUP_DEVELOPERS"
  "$USER_READONLY|$GROUP_READONLY"
  "$MY_IAM_USER|$GROUP_ADMINS"
)

for entry in "${IAM_USERS[@]}"; do
  IFS='|' read -r user group <<< "$entry"

  if iam_exists user "$user"; then
    skip "uzytkownik $user juz istnieje"
  else
    aws_cli iam create-user --user-name "$user" --tags $TAGS >/dev/null
    ok "utworzony uzytkownik $user"
  fi

  if aws_cli iam get-group --group-name "$group" \
       --query 'Users[].UserName' --output text | grep -qw "$user"; then
    skip "  $user jest juz w grupie $group"
  else
    aws_cli iam add-user-to-group --user-name "$user" --group-name "$group"
    ok "  $user dodany do grupy $group"
  fi
done

# ---------------------------------------------------------------------------
# 4. Klucze dostepu i profil AWS CLI dla wlasnego uzytkownika.
#    To jest ten krok, po ktorym przestajemy pracowac na koncie root.
# ---------------------------------------------------------------------------
header "Klucze dostepu dla $MY_IAM_USER"
KEY_FILE="$SECRETS_DIR/${MY_IAM_USER}-accesskey.json"

if [ -f "$KEY_FILE" ]; then
  skip "klucz zapisany juz w .secrets/$(basename "$KEY_FILE") - nie tworze drugiego"
elif [ "$(aws_cli iam list-access-keys --user-name "$MY_IAM_USER" \
            --query 'length(AccessKeyMetadata)' --output text)" != "0" ]; then
  warn "$MY_IAM_USER ma juz klucz w AWS, ale nie ma go lokalnie."
  warn "Sekret pokazywany jest tylko raz - usun stary klucz i uruchom skrypt ponownie:"
  warn "  aws iam delete-access-key --user-name $MY_IAM_USER --access-key-id <ID>"
else
  aws_cli iam create-access-key --user-name "$MY_IAM_USER" > "$KEY_FILE"
  chmod 600 "$KEY_FILE" 2>/dev/null || true
  ok "klucz zapisany w .secrets/$(basename "$KEY_FILE") (katalog jest w .gitignore)"
fi

if [ -f "$KEY_FILE" ]; then
  AK_ID="$(grep -o '"AccessKeyId": *"[^"]*"' "$KEY_FILE" | cut -d'"' -f4)"
  AK_SECRET="$(grep -o '"SecretAccessKey": *"[^"]*"' "$KEY_FILE" | cut -d'"' -f4)"

  aws configure set aws_access_key_id     "$AK_ID"     --profile "$CLI_PROFILE"
  aws configure set aws_secret_access_key "$AK_SECRET" --profile "$CLI_PROFILE"
  aws configure set region                "$AWS_REGION" --profile "$CLI_PROFILE"
  aws configure set output                json          --profile "$CLI_PROFILE"
  ok "profil AWS CLI '$CLI_PROFILE' skonfigurowany dla $MY_IAM_USER"

  # Nowy klucz bywa widoczny dopiero po chwili (IAM jest eventually consistent).
  for attempt in 1 2 3 4 5; do
    if aws --profile "$CLI_PROFILE" sts get-caller-identity >/dev/null 2>&1; then
      break
    fi
    info "  czekam, az klucz sie propaguje (proba $attempt/5)..."
    sleep 5
  done
  capture "$EV" "kim jestem na profilu $CLI_PROFILE" -- \
    aws --profile "$CLI_PROFILE" sts get-caller-identity --output json
fi

# ---------------------------------------------------------------------------
# 5. Dowod wykonania zadania.
# ---------------------------------------------------------------------------
header "Weryfikacja"
capture "$EV" "grupy w koncie"      -- aws_cli iam list-groups --output table
capture "$EV" "uzytkownicy w koncie" -- aws_cli iam list-users --query 'Users[].UserName' --output json

for entry in "${IAM_USERS[@]}"; do
  IFS='|' read -r user _ <<< "$entry"
  capture "$EV" "grupy uzytkownika $user" -- \
    aws_cli iam list-groups-for-user --user-name "$user" --query 'Groups[].GroupName' --output json
done

info ""
ok "Zadanie domowe 1 (IAM) gotowe. Wynik w evidence/$EV"
info "Od teraz pracuj na profilu IAM, nie na roocie:"
info "  export AWS_PROFILE=$CLI_PROFILE"
