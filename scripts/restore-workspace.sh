#!/bin/bash
set -e

echo "::group::Restore workspace"

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$PWD}"
RESTORE_DIR="/tmp/workspace-restore"

if [ -f "$RESTORE_DIR/workspace.tar.gz" ]; then
  echo "Restoring workspace from previous session..."
  tar -xzf "$RESTORE_DIR/workspace.tar.gz" -C "$WORKSPACE_DIR" 2>/dev/null || {
    echo "Warning: Failed to extract workspace (may be corrupt or empty)"
  }
  echo "Workspace restored"

  if [ -f "$RESTORE_DIR/vscode-state.tar.gz" ] && [ -s "$RESTORE_DIR/vscode-state.tar.gz" ]; then
    mkdir -p /tmp/vscode-data
    tar -xzf "$RESTORE_DIR/vscode-state.tar.gz" -C /tmp/vscode-data 2>/dev/null || true
    echo "VS Code state restored"
  fi
else
  echo "No previous workspace artifact found - starting fresh"
fi

echo "::endgroup::"
