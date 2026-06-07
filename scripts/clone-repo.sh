#!/bin/bash
# Best-effort clone: never fails the workflow. Reports target via $GITHUB_OUTPUT.
# (No `set -e` — the script is designed to always exit 0.)

echo "::group::Clone repository"

CLONE_REPO="${CLONE_REPO:-}"
CLONE_REF="${CLONE_REF:-}"
GIT_PAT="${GIT_PAT:-}"
GIT_USER_NAME="${GIT_USER_NAME:-git}"
IDE_ROOT_DIR="${IDE_ROOT_DIR:-/home/runner/work}"

if [ -z "$CLONE_REPO" ]; then
  echo "No clone-repo input, skipping"
  echo "target=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# --- Parse input into URL + name ---
REPO_URL=""
REPO_NAME=""

if [[ "$CLONE_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  REPO_URL="https://github.com/${CLONE_REPO}.git"
  REPO_NAME="${CLONE_REPO##*/}"
elif [[ "$CLONE_REPO" =~ ^https?:// ]]; then
  REPO_URL="$CLONE_REPO"
  REPO_NAME="$(basename "$CLONE_REPO" .git)"
elif [[ "$CLONE_REPO" =~ ^git@ ]]; then
  REPO_URL="$CLONE_REPO"
  REPO_NAME="$(basename "$CLONE_REPO" .git)"
else
  echo "ERROR: Unrecognized clone-repo format: $CLONE_REPO"
  echo "Expected: owner/name, https://…, or git@…"
  echo "target=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Edge case: empty repo name (e.g. user passed https://github.com/)
if [ -z "$REPO_NAME" ]; then
  echo "ERROR: could not derive repo name from $CLONE_REPO"
  echo "target=" >> "$GITHUB_OUTPUT"
  exit 0
fi

TARGET="${IDE_ROOT_DIR}/${REPO_NAME}"
mkdir -p "$IDE_ROOT_DIR"

# --- Skip if already cloned (restore case) ---
if [ -d "$TARGET" ]; then
  if [ -d "$TARGET/.git" ]; then
    echo "Repo already cloned at $TARGET, skipping"
  else
    echo "Directory $TARGET exists but is not a git repo; leaving as-is"
  fi
  echo "target=$TARGET" >> "$GITHUB_OUTPUT"
  exit 0
fi

# --- Wire up credentials for private repos ---
CLONE_CMD_ARGS=(clone --depth 1)
if [ -n "$CLONE_REF" ]; then
  CLONE_CMD_ARGS+=(--branch "$CLONE_REF" --single-branch)
fi

if [ -n "$GIT_PAT" ] && [[ "$REPO_URL" =~ ^https://github.com/ ]]; then
  # Mask the PAT in any future log lines
  echo "::add-mask::$GIT_PAT"
  # Inject PAT into the URL so HTTPS auth works without prompting
  REPO_URL="https://${GIT_USER_NAME}:${GIT_PAT}@${REPO_URL#https://}"
fi

echo "Cloning $REPO_URL into $TARGET ..."

# Redirect to log file (NOT a `tee` pipeline) so the exit code reflects git's status.
if git "${CLONE_CMD_ARGS[@]}" "$REPO_URL" "$TARGET" > /tmp/clone-repo.log 2>&1; then
  echo "Clone successful"
  echo "target=$TARGET" >> "$GITHUB_OUTPUT"
else
  echo "ERROR: git clone failed (see /tmp/clone-repo.log):"
  tail -30 /tmp/clone-repo.log
  echo "target=" >> "$GITHUB_OUTPUT"
  exit 0  # do not fail the workflow
fi

echo "::endgroup::"
