#!/usr/bin/env bash
# Lekcja 28, zadanie domowe 2, punkty 2-5 - listowanie zasobow przez AWS CLI.
#
#   2. AMI Amazon Linux 2
#   3. security groups
#   4. uzytkownicy IAM + szczegoly kazdego z nich
#   5. jedna wybrana usluga - tutaj VPC (siec, w ktorej wyladuje EC2 z lekcji 29)
#
# Kazde polecenie i jego wynik ladują w evidence/04-cli-report.txt, wiec README
# cytuje prawdziwe wyjscie, a nie przepisane z instrukcji.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_lesson_profile

EV=04-cli-report.txt
start_evidence "$EV" "Zadanie domowe 2 - raport z AWS CLI"

# inherited_policies <uzytkownik> - wypisuje "grupa: polityki" dla kazdej grupy,
# do ktorej uzytkownik nalezy. Osobna funkcja, bo capture() uruchamia pojedyncze
# polecenie, a tu potrzebna jest petla.
inherited_policies() {
  local user="$1" g
  aws_cli iam list-groups-for-user --user-name "$user" \
    --query 'Groups[].GroupName' --output text | tr '\t' '\n' | while read -r g; do
      g="${g%$'\r'}"
      [ -n "$g" ] || continue
      printf '%s: %s\n' "$g" \
        "$(aws_cli iam list-attached-group-policies --group-name "$g" \
             --query 'AttachedPolicies[].PolicyName' --output text)"
    done
}

# ---------------------------------------------------------------------------
# 2. AMI Amazon Linux 2
# ---------------------------------------------------------------------------
header "AMI Amazon Linux 2"
info "Amazon publikuje setki obrazow - bez --query i sortowania wynik jest"
info "nieczytelny, wiec bierzemy 10 najnowszych."
capture "$EV" "10 najnowszych AMI Amazon Linux 2 (x86_64)" -- aws_cli ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'reverse(sort_by(Images, &CreationDate))[:10].[ImageId,Name,CreationDate]' \
  --output table

# Ten sam wynik da sie dostac bez przeszukiwania listy - SSM Parameter Store
# trzyma wskaznik na aktualny obraz. Tak robi sie to w automatyzacji.
capture "$EV" "aktualny AMI Amazon Linux 2 wprost z SSM Parameter Store" -- aws_cli ssm get-parameters \
  --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --query 'Parameters[].{Parametr:Name,ImageId:Value}' \
  --output json

# ---------------------------------------------------------------------------
# 3. Security groups
# ---------------------------------------------------------------------------
header "Security groups"
capture "$EV" "security groups w regionie $AWS_REGION" -- aws_cli ec2 describe-security-groups \
  --query 'SecurityGroups[].{Nazwa:GroupName,Id:GroupId,Vpc:VpcId,Opis:Description}' \
  --output table

capture "$EV" "reguly wejsciowe kazdej grupy" -- aws_cli ec2 describe-security-groups \
  --query 'SecurityGroups[].{Nazwa:GroupName,Wejscie:IpPermissions[].{Protokol:IpProtocol,Od:FromPort,Do:ToPort,Zrodla:IpRanges[].CidrIp}}' \
  --output json

# ---------------------------------------------------------------------------
# 4. Uzytkownicy IAM i ich szczegoly
# ---------------------------------------------------------------------------
header "Uzytkownicy IAM"
capture "$EV" "wszyscy uzytkownicy" -- aws_cli iam list-users \
  --query 'Users[].UserName' --output json

capture "$EV" "przeglad uzytkownikow" -- aws_cli iam list-users \
  --query 'Users[].{Nazwa:UserName,Id:UserId,Utworzony:CreateDate,Arn:Arn}' \
  --output table

for user in "$USER_ADMIN" "$USER_DEV" "$USER_READONLY" "$MY_IAM_USER"; do
  header "Szczegoly: $user"
  capture "$EV" "$user - dane konta" -- aws_cli iam get-user --user-name "$user" \
    --query 'User.{Nazwa:UserName,Arn:Arn,Utworzony:CreateDate,Tagi:Tags}' --output json
  capture "$EV" "$user - grupy" -- aws_cli iam list-groups-for-user --user-name "$user" \
    --query 'Groups[].GroupName' --output json
  # Uprawnienia siedza na grupach, wiec ta lista jest celowo pusta -
  # to widoczny dowod, ze polityk nie przypieto bezposrednio do uzytkownika.
  capture "$EV" "$user - polityki podpiete wprost do uzytkownika (ma byc pusto)" -- \
    aws_cli iam list-attached-user-policies --user-name "$user" \
    --query 'AttachedPolicies[].PolicyName' --output json
  capture "$EV" "$user - uprawnienia dziedziczone z grup" -- inherited_policies "$user"
  capture "$EV" "$user - klucze dostepu" -- aws_cli iam list-access-keys --user-name "$user" \
    --query 'AccessKeyMetadata[].{Klucz:AccessKeyId,Status:Status,Utworzony:CreateDate}' --output json
done

# ---------------------------------------------------------------------------
# 5. Wybrana usluga: VPC
# ---------------------------------------------------------------------------
header "Wybrana usluga - VPC"
info "VPC to siec, w ktorej na lekcji 29 wyladuja instancje EC2 - dlatego warto"
info "wiedziec, co juz jest na koncie, zanim cokolwiek w niej uruchomimy."

capture "$EV" "VPC w regionie $AWS_REGION" -- aws_cli ec2 describe-vpcs \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,Domyslna:IsDefault,Stan:State}' \
  --output table

capture "$EV" "podsieci wraz ze strefami dostepnosci" -- aws_cli ec2 describe-subnets \
  --query 'sort_by(Subnets, &AvailabilityZone)[].{Podsiec:SubnetId,Strefa:AvailabilityZone,Cidr:CidrBlock,WolneIP:AvailableIpAddressCount,Vpc:VpcId}' \
  --output table

capture "$EV" "strefy dostepnosci w regionie" -- aws_cli ec2 describe-availability-zones \
  --query 'AvailabilityZones[].{Strefa:ZoneName,Id:ZoneId,Stan:State}' \
  --output table

info ""
ok "Zadanie domowe 2 (raport CLI) gotowe. Wynik w evidence/$EV"
