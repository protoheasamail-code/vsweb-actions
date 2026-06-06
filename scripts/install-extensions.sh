#!/bin/bash
set -e

echo "::group::Install VS Code extensions"

VSCODE_BIN="$1"
EXTENSIONS_LIST="${EXTENSIONS:-}"

if [ -z "$VSCODE_BIN" ] || [ ! -f "$VSCODE_BIN" ]; then
  echo "Usage: install-extensions.sh <path-to-openvscode-server-binary>"
  echo "Extensions from ENV: \$EXTENSIONS"
  exit 1
fi

IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS_LIST"

for ext in "${EXT_ARRAY[@]}"; do
  ext=$(echo "$ext" | xargs)
  if [ -n "$ext" ]; then
    echo "Installing $ext..."
    "$VSCODE_BIN" --install-extension "$ext" --accept-license 2>/dev/null || {
      echo "Warning: Failed to install $ext (may be incompatible or already installed)"
    }
  fi
done

echo "::endgroup::"
