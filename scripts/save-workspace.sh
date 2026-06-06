#!/bin/bash
set -e

MODE="${1:-final}"
echo "::group::Save workspace ($MODE)"

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$PWD}"

if [ "$MODE" = "final" ]; then
  if [ -f /tmp/vscode-pids ]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < /tmp/vscode-pids
    rm -f /tmp/vscode-pids
  fi
fi

rm -f "$WORKSPACE_DIR/SESSION_INACTIVITY_WARNING.md"

# Package workspace
echo "Creating workspace archive..."
tar -czf /tmp/workspace.tar.gz \
  --exclude=.git \
  --exclude=.gitignore \
  --exclude=node_modules \
  --exclude=build \
  --exclude=target \
  --exclude=.gradle \
  --exclude=.kotlin \
  --exclude=__pycache__ \
  --exclude='*.class' \
  --exclude='*.pyc' \
  -C "$WORKSPACE_DIR" . \
  2>/dev/null || {
    echo "Warning: workspace tar had issues (might be empty or permissions)"
    tar -czf /tmp/workspace.tar.gz --ignore-failed-read \
      --exclude=.git -C "$WORKSPACE_DIR" . 2>/dev/null || true
  }

# Package VS Code state
echo "Creating VS Code state archive..."
if [ -d /tmp/vscode-data ] && [ "$(find /tmp/vscode-data -mindepth 1 2>/dev/null | head -1)" ]; then
  tar -czf /tmp/vscode-state.tar.gz -C /tmp/vscode-data . 2>/dev/null || true
else
  touch /tmp/vscode-state.tar.gz
fi

echo "Workspace size: $(du -sh /tmp/workspace.tar.gz 2>/dev/null | cut -f1 || echo '?')"
echo "State size: $(du -sh /tmp/vscode-state.tar.gz 2>/dev/null | cut -f1 || echo '?')"

echo "::endgroup::"
