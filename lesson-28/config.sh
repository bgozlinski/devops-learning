#!/usr/bin/env bash
# Lekcja 28 - wspolna konfiguracja wszystkich skryptow.
# Kazda wartosc mozna nadpisac zmienna srodowiskowa, np.:
#   ALERT_EMAIL=ktos@example.com ./scripts/02-budget-alert.sh

# Region roboczy - ten sam trafia do bucketu S3 i do zapytan EC2.
export AWS_REGION="${AWS_REGION:-eu-central-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Adres, na ktory AWS Budgets wysle alert o przekroczeniu progu.
export ALERT_EMAIL="${ALERT_EMAIL:-bartlomiej.gozlinski@gmail.com}"

# Miesieczny limit budzetu w USD (zadanie domowe 1).
export BUDGET_LIMIT="${BUDGET_LIMIT:-10}"
export BUDGET_NAME="${BUDGET_NAME:-lesson28-monthly-budget}"

# Wlasny uzytkownik IAM - to nim, a nie rootem, pracujemy po tej lekcji.
export MY_IAM_USER="${MY_IAM_USER:-bgozlinski}"

# Nazwa profilu AWS CLI tworzonego dla powyzszego uzytkownika.
export CLI_PROFILE="${CLI_PROFILE:-lesson-28}"

# Prefiks nazw zasobow - pozwala je pozniej odnalezc i posprzatac.
export PREFIX="${PREFIX:-lesson28}"

# Nazwa bucketu S3. Musi byc globalnie unikalna w calym AWS.
export BUCKET_NAME="${BUCKET_NAME:-${PREFIX}-${MY_IAM_USER}-hw2}"

# Uzytkownicy i grupy tworzone w zadaniu domowym 1.
export GROUP_ADMINS="${PREFIX}-admins"
export GROUP_DEVELOPERS="${PREFIX}-developers"
export GROUP_READONLY="${PREFIX}-readonly"

export USER_ADMIN="admin.user"
export USER_DEV="dev.user"
export USER_READONLY="readonly.user"

# Wlasna polityka pokazujaca, jak wyglada dokument JSON uprawnien.
export DEVELOPER_POLICY_NAME="${PREFIX}-developer-policy"
