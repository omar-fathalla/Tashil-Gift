#!/usr/bin/env bash
# TAG-74: log-based metrics + hourly e-mail alerts for failed claims, failed
# receipt saves and Gemini errors. Idempotent (re-running updates in place).
#
#   bash tool/monitoring/setup_alerts.sh <gcp-project-id> <alert-email> [--dry-run]
#
# Run it on tashil-gift-dev first. Running it on production needs Mohamed's
# approval (it only adds metrics/alerts; it never changes data or functions).
# Needs: gcloud signed in with roles/logging.configWriter and
# roles/monitoring.editor on the project.
set -euo pipefail

PROJECT="${1:-}"
EMAIL="${2:-}"
DRY="${3:-}"
if [[ -z "$PROJECT" || -z "$EMAIL" ]]; then
  echo "usage: $0 <gcp-project-id> <alert-email> [--dry-run]" >&2
  exit 2
fi

run() {
  if [[ "$DRY" == "--dry-run" ]]; then printf '[dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi
}

# name|description|filter|threshold per hour
METRICS=(
  "tashil_claim_failures|decrementCampaignPrize refused or failed a claim|jsonPayload.fn=\"decrementCampaignPrize\" AND severity>=WARNING|20"
  "tashil_receipt_save_failures|The rep app reported a failed receipt save (logReceiptSaveFailure)|jsonPayload.message=\"receipt_save_failure\"|10"
  "tashil_gemini_errors|geminiGenerate upstream or network errors|textPayload:\"geminiGenerate\" AND severity>=ERROR|30"
)

BASE='resource.type="cloud_run_revision"'

for row in "${METRICS[@]}"; do
  IFS='|' read -r name desc filter _ <<<"$row"
  full="$BASE AND $filter"
  if gcloud logging metrics describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    run gcloud logging metrics update "$name" --project="$PROJECT" --description="$desc" --log-filter="$full"
  else
    run gcloud logging metrics create "$name" --project="$PROJECT" --description="$desc" --log-filter="$full"
  fi
done

# One e-mail channel, reused.
CHANNEL="$(gcloud beta monitoring channels list --project="$PROJECT" \
  --filter="type=\"email\" AND labels.email_address=\"$EMAIL\"" --format='value(name)' 2>/dev/null | head -n1 || true)"
if [[ -z "$CHANNEL" ]]; then
  if [[ "$DRY" == "--dry-run" ]]; then
    CHANNEL="projects/$PROJECT/notificationChannels/DRY_RUN"
    run gcloud beta monitoring channels create --project="$PROJECT" --type=email --display-name="Tashil alerts" --channel-labels="email_address=$EMAIL"
  else
    CHANNEL="$(gcloud beta monitoring channels create --project="$PROJECT" --type=email \
      --display-name="Tashil alerts" --channel-labels="email_address=$EMAIL" --format='value(name)')"
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for row in "${METRICS[@]}"; do
  IFS='|' read -r name desc _ threshold <<<"$row"
  display="Tashil: $name > $threshold/hour"
  cat >"$TMP/$name.json" <<JSON
{
  "displayName": "$display",
  "documentation": {"content": "$desc. Check Cloud Logging for the entries of the last hour (see docs/08-ci-cd-and-release.md, Monitoring).", "mimeType": "text/markdown"},
  "combiner": "OR",
  "conditions": [{
    "displayName": "$name over $threshold in 1 hour",
    "conditionThreshold": {
      "filter": "metric.type=\"logging.googleapis.com/user/$name\" AND resource.type=\"cloud_run_revision\"",
      "aggregations": [{"alignmentPeriod": "3600s", "perSeriesAligner": "ALIGN_SUM", "crossSeriesReducer": "REDUCE_SUM"}],
      "comparison": "COMPARISON_GT",
      "thresholdValue": $threshold,
      "duration": "0s",
      "trigger": {"count": 1}
    }
  }],
  "notificationChannels": ["$CHANNEL"],
  "enabled": true
}
JSON
  existing="$(gcloud alpha monitoring policies list --project="$PROJECT" \
    --filter="displayName=\"$display\"" --format='value(name)' 2>/dev/null | head -n1 || true)"
  if [[ -n "$existing" ]]; then
    run gcloud alpha monitoring policies update "$existing" --project="$PROJECT" --policy-from-file="$TMP/$name.json"
  else
    run gcloud alpha monitoring policies create --project="$PROJECT" --policy-from-file="$TMP/$name.json"
  fi
done
echo "TAG-74 monitoring set up on $PROJECT (alerts to $EMAIL)."
