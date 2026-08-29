#!/usr/bin/env bash
# Lekcja 28, zadanie domowe 1 - monitoring i alerting.
#
# Tworzy miesieczny budzet kosztowy z dwoma powiadomieniami e-mail:
#   ACTUAL     > 80%  - "wydales juz 8 z 10 USD"
#   FORECASTED > 100% - "w tym tempie przekroczysz 10 USD przed koncem miesiaca"
#
# Prog prognozowany jest wazniejszy od faktycznego: ostrzega zanim pieniadze
# zostana wydane, a nie po fakcie.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_lesson_profile

EV=02-budget.txt
start_evidence "$EV" "Zadanie domowe 1 - budzet i alerty"

ACCOUNT="$(account_id)"

header "Budzet $BUDGET_NAME"

BUDGET_JSON=$(cat <<JSON
{
  "BudgetName": "$BUDGET_NAME",
  "BudgetLimit": { "Amount": "$BUDGET_LIMIT", "Unit": "USD" },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostTypes": {
    "IncludeTax": true,
    "IncludeSubscription": true,
    "UseBlended": false,
    "IncludeRefund": false,
    "IncludeCredit": false,
    "IncludeUpfront": true,
    "IncludeRecurring": true,
    "IncludeOtherSubscription": true,
    "IncludeSupport": true,
    "IncludeDiscount": true,
    "UseAmortized": false
  }
}
JSON
)

NOTIFICATIONS_JSON=$(cat <<JSON
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      { "SubscriptionType": "EMAIL", "Address": "$ALERT_EMAIL" }
    ]
  },
  {
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 100,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      { "SubscriptionType": "EMAIL", "Address": "$ALERT_EMAIL" }
    ]
  }
]
JSON
)

if aws_cli budgets describe-budget --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME" >/dev/null 2>&1; then
  skip "budzet $BUDGET_NAME juz istnieje - aktualizuje limit do ${BUDGET_LIMIT} USD"
  aws_cli budgets update-budget --account-id "$ACCOUNT" --new-budget "$BUDGET_JSON"
else
  aws_cli budgets create-budget \
    --account-id "$ACCOUNT" \
    --budget "$BUDGET_JSON" \
    --notifications-with-subscribers "$NOTIFICATIONS_JSON"
  ok "utworzony budzet $BUDGET_NAME (${BUDGET_LIMIT} USD / miesiac)"
  ok "alerty ACTUAL>80% i FORECASTED>100% ida na $ALERT_EMAIL"
fi

header "Weryfikacja"
capture "$EV" "definicja budzetu" -- aws_cli budgets describe-budget \
  --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME" \
  --query 'Budget.{Nazwa:BudgetName,Limit:BudgetLimit,Okres:TimeUnit,Typ:BudgetType,Wydano:CalculatedSpend.ActualSpend}' \
  --output json

capture "$EV" "skonfigurowane powiadomienia" -- aws_cli budgets describe-notifications-for-budget \
  --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME" --output table

for ntype in ACTUAL FORECASTED; do
  threshold=80; [ "$ntype" = FORECASTED ] && threshold=100
  capture "$EV" "odbiorcy alertu $ntype > ${threshold}%" -- aws_cli budgets describe-subscribers-for-notification \
    --account-id "$ACCOUNT" --budget-name "$BUDGET_NAME" \
    --notification "NotificationType=$ntype,ComparisonOperator=GREATER_THAN,Threshold=$threshold,ThresholdType=PERCENTAGE" \
    --output json
done

info ""
ok "Zadanie domowe 1 (budzet) gotowe. Wynik w evidence/$EV"
info "Podglad w konsoli: https://console.aws.amazon.com/billing/home#/budgets"
