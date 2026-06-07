#!/bin/bash
set -e

MODE="${1:-final}"
echo "::group::Save workspace ($MODE)"

IDE_ROOT_DIR="${IDE_ROOT_DIR:-/home/runner/work}"

if [ "$MODE" = "final" ]; then
  if [ -f /tmp/vscode-pids ]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < /tmp/vscode-pids
    rm -f /tmp/vscode-pids
  fi
fi

rm -f "$IDE_ROOT_DIR/SESSION_INACTIVITY_WARNING.md"

# Compute the workflow's own repo path so we can path-specifically exclude
# its .git/ (which would be a fresh origin clone anyway). All other .git/
# directories (e.g., in clone-repo targets) ARE included so local commits survive.
GITHUB_REPO_NAME="$(basename "${GITHUB_REPOSITORY:-}")"
if [ -n "$GITHUB_REPO_NAME" ]; then
  WORKFLOW_GIT_EXCLUDE="./${GITHUB_REPO_NAME}/${GITHUB_REPO_NAME}/.git"
else
  WORKFLOW_GIT_EXCLUDE=""
fi

# Package workspace
echo "Creating workspace archive from $IDE_ROOT_DIR ..."

if ! tar -czf /tmp/workspace.tar.gz \
    --ignore-failed-read \
    --exclude=.gitignore \
    --exclude=node_modules \
    --exclude=build \
    --exclude=target \
    --exclude=.gradle \
    --exclude=.kotlin \
    --exclude=__pycache__ \
    --exclude='*.class' \
    --exclude='*.pyc' \
    --exclude='_actions' \
    --exclude='_temp' \
    --exclude='_PipelineMapping' \
    --exclude='_runner_file_commands' \
    --exclude='_diag' \
    ${WORKFLOW_GIT_EXCLUDE:+--exclude="$WORKFLOW_GIT_EXCLUDE"} \
    -C "$IDE_ROOT_DIR" . \
    > /tmp/save-workspace.log 2>&1; then
  echo "ERROR: workspace tar failed (see /tmp/save-workspace.log):"
  tail -50 /tmp/save-workspace.log
  exit 1
fi

# Package VS Code state
echo "Creating VS Code state archive..."
if [ -d /tmp/vscode-data ] && [ "$(find /tmp/vscode-data -mindepth 1 2>/dev/null | head -1)" ]; then
  tar -czf /tmp/vscode-state.tar.gz -C /tmp/vscode-data . > /tmp/save-state.log 2>&1 || {
    echo "WARNING: state tar failed (see /tmp/save-state.log):"
    tail -20 /tmp/save-state.log
  }
else
  touch /tmp/vscode-state.tar.gz
fi

# Verification
if [ ! -s /tmp/workspace.tar.gz ]; then
  echo "ERROR: /tmp/workspace.tar.gz is empty or missing"
  exit 1
fi

WS_SIZE=$(du -sh /tmp/workspace.tar.gz | cut -f1)
WS_LIST=$(tar -tzf /tmp/workspace.tar.gz 2>/dev/null || true)
WS_COUNT=$(printf '%s\n' "$WS_LIST" | wc -l)
ST_SIZE=$(du -sh /tmp/vscode-state.tar.gz 2>/dev/null | cut -f1 || echo '?')
ST_LIST=$(tar -tzf /tmp/vscode-state.tar.gz 2>/dev/null || true)
ST_COUNT=$(printf '%s\n' "$ST_LIST" | wc -l)

echo "[save] mode=$MODE workspace=${WS_SIZE} (${WS_COUNT} files) state=${ST_SIZE} (${ST_COUNT} files)"
echo "[save] workspace top-level entries:"
printf '%s\n' "$WS_LIST" | head -20 | sed 's/^/  /'

# Toolchain leakage check (regression guard — JDK/SDK must NOT be in the snapshot)
LEAKED=$(printf '%s\n' "$WS_LIST" | grep -cE 'opt/hostedtoolcache|usr/local/lib/android' || true)
if [ "$LEAKED" -gt 0 ]; then
  echo "WARNING: $LEAKED toolchain paths found in snapshot (should be 0):"
  printf '%s\n' "$WS_LIST" | grep -E 'opt/hostedtoolcache|usr/local/lib/android' | head -10 | sed 's/^/  /'
fi

echo "::endgroup::"
