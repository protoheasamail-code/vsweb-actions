#!/bin/bash
set -e

echo "::group::Start IDE"

VSCODE_PORT="${VSCODE_PORT:-3000}"
FILE_SERVER_PORT="${FILE_SERVER_PORT:-3001}"
TUNNEL_PORT="${TUNNEL_PORT:-3001}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDE_ROOT_DIR="${IDE_ROOT_DIR:-/home/runner/work}"
DEFAULT_FOLDER="${DEFAULT_FOLDER:-$IDE_ROOT_DIR}"
WORKSPACE_DIR="$DEFAULT_FOLDER"

mkdir -p /tmp/vscode-data

# --- Generate connection token ---
TOKEN_FILE=/tmp/connection-token
if [ -n "$CONNECTION_TOKEN" ]; then
  echo "$CONNECTION_TOKEN" > "$TOKEN_FILE"
else
  openssl rand -hex 32 > "$TOKEN_FILE"
fi
chmod 600 "$TOKEN_FILE"
CONNECTION_TOKEN=$(cat "$TOKEN_FILE")

# --- Download openvscode-server if not cached ---
VSCODE_DIR="/tmp/openvscode-server"
VSCODE_BIN="$VSCODE_DIR/bin/openvscode-server"

if [ ! -f "$VSCODE_BIN" ]; then
  echo "Downloading openvscode-server..."
  VSCODE_VERSION="latest"
  DOWNLOAD_URL=$(curl -sL "https://api.github.com/repos/gitpod-io/openvscode-server/releases/latest" \
    | grep "browser_download_url.*linux-x64.tar.gz" \
    | head -1 \
    | cut -d'"' -f4)

  if [ -z "$DOWNLOAD_URL" ]; then
    echo "Failed to get download URL, falling back to fixed version..."
    DOWNLOAD_URL="https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v1.109.5/openvscode-server-v1.109.5-linux-x64.tar.gz"
  fi

  curl -sL "$DOWNLOAD_URL" -o /tmp/openvscode-server.tar.gz
  mkdir -p "$VSCODE_DIR"
  tar -xzf /tmp/openvscode-server.tar.gz --strip-components=1 -C "$VSCODE_DIR"
  rm /tmp/openvscode-server.tar.gz
  echo "openvscode-server extracted to $VSCODE_DIR"
fi

# --- Export env ---
echo "VSCODE_BIN=$VSCODE_BIN" >> "$GITHUB_ENV"

# --- Set default VS Code dark theme ---
mkdir -p /tmp/vscode-data/user-data/User
cat > /tmp/vscode-data/user-data/User/settings.json << 'SETTINGS'
{
    "workbench.colorTheme": "Default Dark Modern",
    "workbench.preferredDarkColorTheme": "Default Dark Modern",
    "workbench.preferredLightColorTheme": "Default Dark Modern",
    "window.autoDetectColorScheme": false
}
SETTINGS

# --- Workspace-level settings as a second-layer guarantee ---
mkdir -p "$IDE_ROOT_DIR/.vscode"
cat > "$IDE_ROOT_DIR/.vscode/settings.json" << 'WSETTINGS'
{
    "workbench.colorTheme": "Default Dark Modern",
    "workbench.preferredDarkColorTheme": "Default Dark Modern",
    "workbench.preferredLightColorTheme": "Default Dark Modern"
}
WSETTINGS

# --- Start openvscode-server (token from file, not CLI arg) ---
echo "Starting openvscode-server on port $VSCODE_PORT..."
"$VSCODE_BIN" \
  --port "$VSCODE_PORT" \
  --host 0.0.0.0 \
  --connection-token-file "$TOKEN_FILE" \
  --server-data-dir /tmp/vscode-data \
  --user-data-dir /tmp/vscode-data/user-data \
  --default-folder "$WORKSPACE_DIR" \
  &>/tmp/vscode-server.log &
VSCODE_PID=$!
echo $VSCODE_PID > /tmp/vscode-pids

for i in $(seq 1 30); do
  if curl -so /dev/null "http://localhost:$VSCODE_PORT" 2>/dev/null; then
    echo "openvscode-server ready"
    break
  fi
  sleep 1
done

# --- Pre-install extensions ---
if [ -n "${EXTENSIONS:-}" ]; then
  echo "Pre-installing extensions..."
  IFS=',' read -ra EXT_ARRAY <<< "${EXTENSIONS}"
  for ext in "${EXT_ARRAY[@]}"; do
    ext=$(echo "$ext" | xargs)
    [ -n "$ext" ] && "$VSCODE_BIN" --install-extension "$ext" --accept-license 2>/dev/null || true
  done
fi

# --- Start custom file server (reverse proxy + file explorer) ---
echo "Starting file server on port $FILE_SERVER_PORT..."
CONNECTION_TOKEN="$CONNECTION_TOKEN" node "$SCRIPT_DIR/file-server.mjs" &
FILE_SERVER_PID=$!
echo $FILE_SERVER_PID >> /tmp/vscode-pids

sleep 1

# --- Start cloudflared tunnel ---
echo "Starting Cloudflare tunnel..."
TUNNEL_URL=""

# Get latest cloudflared version via API
CFD_VERSION=$(curl -sL \
  "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" \
  | grep '"tag_name":' | cut -d'"' -f4)

if [ -n "$CFD_VERSION" ]; then
  echo "Downloading cloudflared $CFD_VERSION..."
  CFD_DL_URL="https://github.com/cloudflare/cloudflared/releases/download/${CFD_VERSION}/cloudflared-linux-amd64"
  curl -fL -o /tmp/cloudflared "$CFD_DL_URL" 2>/dev/null || true

  if file /tmp/cloudflared 2>/dev/null | grep -q ELF; then
    chmod +x /tmp/cloudflared

    # Start tunnel
    /tmp/cloudflared tunnel --url "http://localhost:$TUNNEL_PORT" \
      --loglevel debug \
      &>/tmp/tunnel.log &
    TUNNEL_PID=$!
    echo $TUNNEL_PID >> /tmp/vscode-pids

    # Wait for tunnel URL
    for i in $(seq 1 30); do
      TUNNEL_URL=$(grep -oP 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/tunnel.log | head -1 || true)
      if [ -n "$TUNNEL_URL" ]; then break; fi
      sleep 1
    done
  else
    echo "Downloaded file is not a valid binary"
  fi
else
  echo "Could not determine cloudflared version"
fi

if [ -z "$TUNNEL_URL" ]; then
  echo "Warning: Cloudflare tunnel failed, falling back to localhost."
  echo "TUNNEL_URL=http://localhost:$TUNNEL_PORT" >> "$GITHUB_ENV"
else
  echo "TUNNEL_URL=$TUNNEL_URL" >> "$GITHUB_ENV"
  echo "$TUNNEL_URL" > /tmp/tunnel-url

  # Notify Discord with the session URL
  DISCORD_WEBHOOK="$DISCORD_WEBHOOK" \
    bash "$SCRIPT_DIR/discord-notify.sh" \
    "💻 **VS Code IDE started**\nURL: ${TUNNEL_URL}/?tkn=${CONNECTION_TOKEN}\nFile Browser: ${TUNNEL_URL}/files/?tkn=${CONNECTION_TOKEN}"
fi

# --- Optional SSH access ---
if [ "${ENABLE_SSH:-false}" = "true" ]; then
  echo "Setting up SSH access..."

  SSH_KEY_FILE=/tmp/ssh-key
  ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q

  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  cat "$SSH_KEY_FILE.pub" >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys

  sudo systemctl start sshd 2>/dev/null || sudo service ssh start 2>/dev/null || true

  /tmp/cloudflared tunnel --url ssh://localhost:22 --loglevel debug &>/tmp/tunnel-ssh.log &
  SSH_TUNNEL_PID=$!
  echo $SSH_TUNNEL_PID >> /tmp/vscode-pids

  SSH_URL=""
  for i in $(seq 1 15); do
    SSH_URL=$(grep -oP 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/tunnel-ssh.log | head -1 || true)
    if [ -n "$SSH_URL" ]; then break; fi
    sleep 1
  done

  echo "SSH_URL=$SSH_URL" >> "$GITHUB_ENV"

  # Notify Discord with SSH info
  DISCORD_WEBHOOK="$DISCORD_WEBHOOK" \
    bash "$SCRIPT_DIR/discord-notify.sh" \
    "🔑 **SSH enabled**\nHost: ${SSH_URL#https://}"
fi

echo "::endgroup::"
