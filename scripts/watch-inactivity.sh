#!/bin/bash

echo "::group::IDE session started"

VSCODE_PORT="${VSCODE_PORT:-3000}"
INACTIVITY_TIMEOUT="${INACTIVITY_TIMEOUT:-20}"
SESSION_TIMEOUT="${SESSION_TIMEOUT:-360}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f /tmp/connection-token ]; then
  CONNECTION_TOKEN=$(cat /tmp/connection-token)
fi
if [ -f /tmp/tunnel-url ]; then
  TUNNEL_URL=$(cat /tmp/tunnel-url)
fi

IDE_ROOT_DIR="${IDE_ROOT_DIR:-/home/runner/work}"
WARNING_FILE="$IDE_ROOT_DIR/SESSION_INACTIVITY_WARNING.md"
CONTINUE_FILE="/continue"
GRACE_MINUTES=5
START_TIME=$(date +%s)
HALF_STEP=30

echo "Session active. Inactivity timeout: ${INACTIVITY_TIMEOUT}m (grace: ${GRACE_MINUTES}m)"
echo "Job timeout: ${SESSION_TIMEOUT}m (session ends at T-0)"
echo "Create '$CONTINUE_FILE' to end session and save workspace."
echo ""

# Defense-in-depth: mask the token in all subsequent log output
if [ -n "$CONNECTION_TOKEN" ]; then
  echo "::add-mask::$CONNECTION_TOKEN"
fi

cleanup() {
  echo ""
  echo "Shutting down..."
  if [ -f /tmp/vscode-pids ]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < /tmp/vscode-pids
  fi
  rm -f "$WARNING_FILE"

  # Notify Discord that the session ended
  NOW=$(date +%s)
  DURATION=$(( (NOW - START_TIME) / 60 ))
  DISCORD_WEBHOOK="$DISCORD_WEBHOOK" \
    bash "$SCRIPT_DIR/discord-notify.sh" \
    "⏹️ **Session ended** (${DURATION}m active)"
}
trap cleanup EXIT

inactive_count=0
warning_shown=false
timeout_warned=false

while true; do
  sleep "$HALF_STEP"

  if [ -f "$CONTINUE_FILE" ]; then
    echo "Continue file detected. Ending session..."
    exit 0
  fi

  NOW=$(date +%s)
  ELAPSED=$(( (NOW - START_TIME) / 60 ))

  # Check for impending job timeout: save at T-5m
  REMAINING=$(( SESSION_TIMEOUT - ELAPSED ))
  if [ "$REMAINING" -le 1 ]; then
    echo "Job timeout imminent. Ending session..."
    touch "$CONTINUE_FILE"
    exit 0
  fi

  if [ "$REMAINING" -le 5 ] && [ "$timeout_warned" = false ]; then
    echo ""
    echo "⚠️  Job timeout in ${REMAINING}m. Session will end shortly..."
    timeout_warned=true
  fi

  # --- Inactivity detection ---
  CONNECTIONS=$(ss -tn state established 2>/dev/null | grep ":${VSCODE_PORT} " | wc -l || echo 0)

  if [ "$CONNECTIONS" -gt 0 ]; then
    inactive_count=0
    warning_shown=false
    rm -f "$WARNING_FILE" 2>/dev/null || true
    continue
  fi

  # Each sleep is 30s; count each as 0.5 of a minute unit
  inactive_count=$((inactive_count + 1))
  inactive_mins=$((inactive_count / 2))

  if [ "$inactive_mins" -ge "$INACTIVITY_TIMEOUT" ] && [ "$warning_shown" = false ]; then
    echo ""
    echo "⚠️  No activity detected for ${INACTIVITY_TIMEOUT}m"
    echo "Session will auto-shutdown in ${GRACE_MINUTES}m unless activity resumes."
    echo "Touch any file in VS Code or close/reopen the browser tab to reset."
    echo "Create '$CONTINUE_FILE' now to save progress and exit."
    echo ""

    cat > "$WARNING_FILE" <<- WARN
# ⚠️  Inactivity Warning

**No browser activity detected for ${INACTIVITY_TIMEOUT} minutes.**

The session will auto-shutdown in **${GRACE_MINUTES} minutes** unless you:
- Click anywhere in the VS Code editor
- Close and reopen the browser tab
- Or run: \`touch ${CONTINUE_FILE}\` in the terminal

To extend the session, simply interact with the IDE.
WARN

    warning_shown=true
  fi

  if [ "$inactive_mins" -ge "$((INACTIVITY_TIMEOUT + GRACE_MINUTES))" ]; then
    echo ""
    echo "⏰ Session ended due to inactivity."
    touch "$CONTINUE_FILE"
    exit 0
  fi
done
