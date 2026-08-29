#!/usr/bin/env bash
# Lekcja 28, zadanie domowe 2, punkt 1 - bucket S3, wgranie i pobranie pliku.
#
# Pobranie przez interfejs webowy jest z definicji recznym krokiem - skrypt
# robi wersje CLI i wypisuje gotowy link do konsoli, zeby powtorzyc to klikaniem.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_lesson_profile

EV=03-s3.txt
start_evidence "$EV" "Zadanie domowe 2 - operacje na S3"

WORK_DIR="$LESSON_DIR/evidence"
LOCAL_FILE="$WORK_DIR/test.txt"
DOWNLOADED="$WORK_DIR/downloaded.txt"

header "Bucket $BUCKET_NAME"

# Nazwa bucketu jest globalnie unikalna w calym AWS, wiec "juz istnieje" moze
# znaczyc dwie rozne rzeczy: nalezy do nas albo do kogos innego.
if aws_cli s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
  skip "bucket $BUCKET_NAME juz istnieje i nalezy do tego konta"
else
  # Poza us-east-1 trzeba jawnie podac LocationConstraint.
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws_cli s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" >/dev/null
  else
    aws_cli s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
  fi
  ok "utworzony bucket s3://$BUCKET_NAME w regionie $AWS_REGION"
fi

# Domyslne ustawienia S3 sa dzis bezpieczne, ale ustawiamy je jawnie -
# bucket bez tego bywa najczestszym zrodlem wyciekow danych w AWS.
header "Zabezpieczenia bucketu"
aws_cli s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
ok "zablokowany dostep publiczny"

aws_cli s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
ok "wlaczone szyfrowanie po stronie serwera (AES256)"

aws_cli s3api put-bucket-tagging --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=Environment,Value=Learning},{Key=Lesson,Value=28}]'
ok "otagowany Environment=Learning, Lesson=28"

header "Wgranie pliku"
printf 'Hello AWS!\nLekcja 28 - zadanie domowe 2\n' > "$LOCAL_FILE"
info "lokalna tresc pliku:"
sed 's/^/  /' "$LOCAL_FILE"

capture "$EV" "wgranie pliku do bucketu" -- \
  aws_cli s3 cp "$(native_path "$LOCAL_FILE")" "s3://$BUCKET_NAME/test.txt"

header "Listowanie"
capture "$EV" "wszystkie buckety na koncie" -- aws_cli s3 ls
capture "$EV" "zawartosc bucketu"           -- aws_cli s3 ls "s3://$BUCKET_NAME/"
capture "$EV" "metadane obiektu" -- aws_cli s3api head-object \
  --bucket "$BUCKET_NAME" --key test.txt \
  --query '{Rozmiar:ContentLength,Typ:ContentType,Szyfrowanie:ServerSideEncryption,Zmieniony:LastModified}' \
  --output json

header "Pobranie pliku"
rm -f "$DOWNLOADED"
capture "$EV" "pobranie pliku przez CLI" -- \
  aws_cli s3 cp "s3://$BUCKET_NAME/test.txt" "$(native_path "$DOWNLOADED")"

if diff -q "$LOCAL_FILE" "$DOWNLOADED" >/dev/null; then
  ok "pobrany plik jest identyczny z wgranym"
  { printf '\n# weryfikacja: diff test.txt downloaded.txt\n'; printf 'pliki identyczne\n'; } >> "$EVIDENCE_DIR/$EV"
else
  die "pobrany plik rozni sie od wgranego"
fi

info ""
ok "Zadanie domowe 2 (S3) gotowe. Wynik w evidence/$EV"
info ""
info "Pozostaje reczna czesc zadania - pobranie tego samego pliku przez przegladarke:"
info "  https://console.aws.amazon.com/s3/buckets/${BUCKET_NAME}?region=${AWS_REGION}"
info "  zaznacz test.txt -> Download"
