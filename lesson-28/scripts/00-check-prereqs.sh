#!/usr/bin/env bash
# Lekcja 28 - sprawdzenie srodowiska przed wykonaniem zadan domowych.
# Nie tworzy zadnych zasobow, mozna uruchamiac do woli.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EV=00-prereqs.txt
start_evidence "$EV" "Lekcja 28 - sprawdzenie srodowiska"

header "AWS CLI"
command -v aws >/dev/null 2>&1 || die "Nie znaleziono AWS CLI. Instalacja: https://awscli.amazonaws.com/AWSCLIV2.msi"
capture "$EV" "wersja AWS CLI" -- aws --version

header "Tozsamosc"
capture "$EV" "kim jestem dla AWS" -- aws_cli sts get-caller-identity --output json

ARN="$(aws_cli sts get-caller-identity --query Arn --output text)"
if [[ "$ARN" == *":root" ]]; then
  warn "Pracujesz na koncie root ($ARN)."
  warn "To jest dokladnie to, czego lekcja kaze unikac - uruchom 01-iam-structure.sh,"
  warn "a nastepnie przelacz sie na profil '$CLI_PROFILE'."
else
  ok "Uzywasz uzytkownika IAM, nie roota: $ARN"
fi

header "Region"
info "AWS_REGION = $AWS_REGION"
capture "$EV" "czy region jest poprawny" -- aws_cli ec2 describe-availability-zones \
  --region "$AWS_REGION" --query 'AvailabilityZones[].ZoneName' --output text

header "Konfiguracja"
info "Konto:            $(account_id)"
info "Alert budzetowy:  $ALERT_EMAIL (limit ${BUDGET_LIMIT} USD / miesiac)"
info "Bucket S3:        $BUCKET_NAME"
info "Wlasny uzytkownik:$MY_IAM_USER"

if [ "$ALERT_EMAIL" = "change-me@example.com" ]; then
  die "Ustaw ALERT_EMAIL w config.sh zanim uruchomisz 02-budget-alert.sh"
fi

ok "Srodowisko gotowe. Wynik zapisany w evidence/$EV"
