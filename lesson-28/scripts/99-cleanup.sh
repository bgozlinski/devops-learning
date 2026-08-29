#!/usr/bin/env bash
# Lekcja 28 - usuwa wszystko, co utworzyly skrypty 01-03.
#
# Kolejnosc nie jest przypadkowa: AWS nie pozwoli usunac uzytkownika, dopoki ma
# klucze i czlonkostwa w grupach, ani grupy z uzytkownikami w srodku, ani
# polityki, ktora jest gdzies podpieta, ani bucketu, w ktorym cokolwiek lezy.
#
# Uruchomienie wymaga jawnego potwierdzenia:
#   CONFIRM=yes ./scripts/99-cleanup.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [ "${CONFIRM:-}" != "yes" ]; then
  warn "Ten skrypt usuwa zasoby AWS utworzone przez lekcje 28:"
  warn "  uzytkownicy: $USER_ADMIN, $USER_DEV, $USER_READONLY, $MY_IAM_USER"
  warn "  grupy:       $GROUP_ADMINS, $GROUP_DEVELOPERS, $GROUP_READONLY"
  warn "  polityka:    $DEVELOPER_POLICY_NAME"
  warn "  budzet:      $BUDGET_NAME"
  warn "  bucket:      s3://$BUCKET_NAME (razem z zawartoscia)"
  die "Uruchom ponownie z CONFIRM=yes, jesli na pewno tego chcesz."
fi

# Uwaga: sprzatamy takze wlasnego uzytkownika, wiec robimy to danymi logowania
# spoza profilu $CLI_PROFILE - inaczej skrypt usunalby klucz, ktorym dziala.
if [ "${AWS_PROFILE:-}" = "$CLI_PROFILE" ]; then
  warn "Odpinam profil $CLI_PROFILE - nie da sie usunac klucza, ktorym sie pracuje."
  unset AWS_PROFILE
fi

ACCOUNT="$(account_id)"
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${DEVELOPER_POLICY_NAME}"

header "Bucket s3://$BUCKET_NAME"
if aws_cli s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  aws_cli s3 rm "s3://$BUCKET_NAME" --recursive
  aws_cli s3api delete-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
  ok "bucket usuniety"
else
  skip "bucket nie istnieje"
fi

header "Budzet $BUDGET_NAME"
if aws_cli budgets describe-budget --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME" >/dev/null 2>&1; then
  aws_cli budgets delete-budget --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME"
  ok "budzet usuniety"
else
  skip "budzet nie istnieje"
fi

header "Uzytkownicy"
for user in "$USER_ADMIN" "$USER_DEV" "$USER_READONLY" "$MY_IAM_USER"; do
  if ! iam_exists user "$user"; then
    skip "uzytkownik $user nie istnieje"
    continue
  fi

  for key in $(aws_cli iam list-access-keys --user-name "$user" \
                 --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    aws_cli iam delete-access-key --user-name "$user" --access-key-id "$key"
    ok "  usuniety klucz uzytkownika $user"
  done

  for grp in $(aws_cli iam list-groups-for-user --user-name "$user" \
                 --query 'Groups[].GroupName' --output text); do
    aws_cli iam remove-user-from-group --user-name "$user" --group-name "$grp"
    ok "  $user wypisany z grupy $grp"
  done

  for pol in $(aws_cli iam list-attached-user-policies --user-name "$user" \
                 --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws_cli iam detach-user-policy --user-name "$user" --policy-arn "$pol"
  done

  # Haslo do konsoli istnieje tylko, jesli ktos je recznie ustawil.
  aws_cli iam delete-login-profile --user-name "$user" >/dev/null 2>&1 || true

  aws_cli iam delete-user --user-name "$user"
  ok "usuniety uzytkownik $user"
done

header "Grupy"
for grp in "$GROUP_ADMINS" "$GROUP_DEVELOPERS" "$GROUP_READONLY"; do
  if ! iam_exists group "$grp"; then
    skip "grupa $grp nie istnieje"
    continue
  fi
  for pol in $(aws_cli iam list-attached-group-policies --group-name "$grp" \
                 --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws_cli iam detach-group-policy --group-name "$grp" --policy-arn "$pol"
  done
  aws_cli iam delete-group --group-name "$grp"
  ok "usunieta grupa $grp"
done

header "Polityka $DEVELOPER_POLICY_NAME"
if iam_exists policy "$DEVELOPER_POLICY_NAME"; then
  # Polityka moze miec wersje inne niz domyslna - te trzeba usunac osobno.
  for ver in $(aws_cli iam list-policy-versions --policy-arn "$POLICY_ARN" \
                 --query 'Versions[?!IsDefaultVersion].VersionId' --output text); do
    aws_cli iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$ver"
  done
  aws_cli iam delete-policy --policy-arn "$POLICY_ARN"
  ok "usunieta polityka $DEVELOPER_POLICY_NAME"
else
  skip "polityka nie istnieje"
fi

header "Lokalnie"
rm -f "$SECRETS_DIR/${MY_IAM_USER}-accesskey.json"
ok "usuniety lokalny plik z kluczem"
info "Profil '$CLI_PROFILE' zostaje w ~/.aws - jego klucz juz nie dziala."
info "Usuniecie wpisu: aws configure set aws_access_key_id '' --profile $CLI_PROFILE"

info ""
ok "Sprzatanie zakonczone."
