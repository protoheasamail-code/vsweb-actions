#!/bin/bash
set -e

echo "::group::Restore workspace"

IDE_ROOT_DIR="${IDE_ROOT_DIR:-/home/runner/work}"
RESTORE_DIR="/tmp/workspace-restore"
mkdir -p "$IDE_ROOT_DIR"

if [ -f "$RESTORE_DIR/workspace.tar.gz" ] && [ -s "$RESTORE_DIR/workspace.tar.gz" ]; then
  echo "Restoring workspace from previous session into $IDE_ROOT_DIR ..."
  if tar -xzf "$RESTORE_DIR/workspace.tar.gz" -C "$IDE_ROOT_DIR" \
       > /tmp/restore-workspace.log 2>&1; then
    LIST=$(tar -tzf "$RESTORE_DIR/workspace.tar.gz" 2>/dev/null || true)
    EXTRACTED=$(printf '%s\n' "$LIST" | wc -l)
    echo "[restore] workspace: ${EXTRACTED} files extracted"
    echo "[restore] workspace top-level entries:"
    printf '%s\n' "$LIST" | head -10 | sed 's/^/  /'
    if [ "$EXTRACTED" -eq 0 ]; then
      echo "WARNING: 0 files extracted — archive may be empty or wrong format"
    fi
  else
    echo "WARNING: Failed to extract workspace (see /tmp/restore-workspace.log):"
    tail -30 /tmp/restore-workspace.log
  fi

  if [ -f "$RESTORE_DIR/vscode-state.tar.gz" ] && [ -s "$RESTORE_DIR/vscode-state.tar.gz" ]; then
    mkdir -p /tmp/vscode-data
    if tar -xzf "$RESTORE_DIR/vscode-state.tar.gz" -C /tmp/vscode-data \
         > /tmp/restore-state.log 2>&1; then
      ST_LIST=$(tar -tzf "$RESTORE_DIR/vscode-state.tar.gz" 2>/dev/null || true)
      ST_COUNT=$(printf '%s\n' "$ST_LIST" | wc -l)
      echo "[restore] state: ${ST_COUNT} files restored"
    else
      echo "WARNING: Failed to extract state (see /tmp/restore-state.log):"
      tail -20 /tmp/restore-state.log
    fi
  fi
else
  echo "No previous workspace artifact found - starting fresh"
fi

echo "::endgroup::"
