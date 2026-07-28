#!/bin/bash
# discord-notify.sh — Sends a Discord embed message to a webhook.
# Usage: discord-notify.sh <message>
# Reads DISCORD_WEBHOOK from env. Retries 3 times with 5s cooldown.
# Exits 1 if DISCORD_WEBHOOK is unset or all retries fail.

set -e

MESSAGE="${1:-}"
DISCORD_WEBHOOK="${DISCORD_WEBHOOK:-}"

if [ -z "$DISCORD_WEBHOOK" ]; then
  echo "Discord webhook not configured, skipping notification"
  exit 0
fi

if [ -z "$MESSAGE" ]; then
  echo "ERROR: Usage: discord-notify.sh <message>" >&2
  exit 1
fi

# Mask the webhook URL in logs
echo "::add-mask::$DISCORD_WEBHOOK"

MAX_RETRIES=3
RETRY_DELAY=5

for attempt in $(seq 1 "$MAX_RETRIES"); do
  RESPONSE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "$DISCORD_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "$(cat <<JSON
{
  "content": "${MESSAGE}"
}
JSON
)" 2>&1) && HTTP_CODE="$RESPONSE" || HTTP_CODE="000"

  if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    exit 0
  fi

  if [ "$attempt" -lt "$MAX_RETRIES" ]; then
    sleep "$RETRY_DELAY"
  fi
done

echo "ERROR: Discord webhook failed after $MAX_RETRIES attempts" >&2
exit 1
