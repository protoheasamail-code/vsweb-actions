#!/bin/bash
set -e

echo "::group::Start IDE"

VSCODE_PORT="${VSCODE_PORT:-3000}"
FILE_SERVER_PORT="${FILE_SERVER_PORT:-3001}"
TUNNEL_PORT="${TUNNEL_PORT:-3001}"
TUNNEL_PROVIDER="${TUNNEL_PROVIDER:-cloudflared}"
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_FUNNEL="${TAILSCALE_FUNNEL:-false}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-}"
ENABLE_SSH="${ENABLE_SSH:-false}"

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

# ============================================================================
# Cloudflare tunnel
# ============================================================================
setup_cloudflared() {
  echo "Setting up Cloudflare tunnel..."

  CFD_VERSION=$(curl -sL \
    "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" \
    | grep '"tag_name":' | cut -d'"' -f4)

  if [ -n "$CFD_VERSION" ]; then
    echo "Downloading cloudflared $CFD_VERSION..."
    CFD_DL_URL="https://github.com/cloudflare/cloudflared/releases/download/${CFD_VERSION}/cloudflared-linux-amd64"
    curl -fL -o /tmp/cloudflared "$CFD_DL_URL" 2>/dev/null || true

    if file /tmp/cloudflared 2>/dev/null | grep -q ELF; then
      chmod +x /tmp/cloudflared
      return 0
    else
      echo "Downloaded file is not a valid binary"
      return 1
    fi
  else
    echo "Could not determine cloudflared version"
    return 1
  fi
}

start_cloudflared_tunnel() {
  /tmp/cloudflared tunnel --url "http://localhost:$TUNNEL_PORT" \
    --loglevel debug \
    &>/tmp/tunnel.log &
  TUNNEL_PID=$!
  echo $TUNNEL_PID >> /tmp/vscode-pids

  TUNNEL_URL=""
  for i in $(seq 1 30); do
    TUNNEL_URL=$(grep -oP 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/tunnel.log | head -1 || true)
    if [ -n "$TUNNEL_URL" ]; then break; fi
    sleep 1
  done

  if [ -z "$TUNNEL_URL" ]; then
    echo "Warning: Cloudflare tunnel failed"
    return 1
  fi

  echo "$TUNNEL_URL" > /tmp/tunnel-url
  return 0
}

start_cloudflared_ssh_tunnel() {
  /tmp/cloudflared tunnel --url ssh://localhost:22 --loglevel debug &>/tmp/tunnel-ssh.log &
  SSH_TUNNEL_PID=$!
  echo $SSH_TUNNEL_PID >> /tmp/vscode-pids

  SSH_URL=""
  for i in $(seq 1 15); do
    SSH_URL=$(grep -oP 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' /tmp/tunnel-ssh.log | head -1 || true)
    if [ -n "$SSH_URL" ]; then break; fi
    sleep 1
  done

  echo "$SSH_URL" > /tmp/ssh-tunnel-url
}

# ============================================================================
# Tailscale
# ============================================================================
setup_tailscale() {
  echo "Setting up Tailscale..."

  if command -v tailscale &>/dev/null && sudo tailscale status &>/dev/null 2>&1; then
    echo "Tailscale already running"
    return 0
  fi

  echo "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null || {
    echo "ERROR: Tailscale install failed"
    return 1
  }

  if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    echo "ERROR: tailscale-auth-key is required when using Tailscale"
    return 1
  fi

  echo "Joining Tailscale network..."
  TS_HOSTNAME_FLAG=""
  if [ -n "$TAILSCALE_HOSTNAME" ]; then
    TS_HOSTNAME_FLAG="--hostname=$TAILSCALE_HOSTNAME"
    echo "Using fixed hostname: $TAILSCALE_HOSTNAME"
  else
    TS_HOSTNAME_FLAG="--hostname=$(hostname)"
  fi
  sudo tailscale up --auth-key="$TAILSCALE_AUTH_KEY" $TS_HOSTNAME_FLAG 2>&1 || {
    echo "ERROR: Tailscale up failed"
    return 1
  }

  # Enable Tailscale SSH (uses Tailscale identity for auth)
  if [ "$ENABLE_SSH" = "true" ]; then
    echo "Enabling Tailscale SSH..."
    sudo tailscale set --ssh 2>&1 || {
      echo "Warning: Failed to enable Tailscale SSH (non-fatal)"
    }
  fi

  return 0
}

get_tailscale_hostname() {
  # jq is available on GitHub Actions runners (Node.js ships with it)
  sudo tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' 2>/dev/null || true
}

start_tailscale_tunnel() {
  TAILSCALE_HOSTNAME=$(get_tailscale_hostname)

  if [ "$TAILSCALE_FUNNEL" = "true" ]; then
    echo "Starting Tailscale Funnel for HTTP..."
    sudo tailscale funnel --bg "http://localhost:$TUNNEL_PORT" 2>&1 || {
      echo "Warning: Tailscale Funnel failed (non-fatal)"
    }
    TUNNEL_URL="https://${TAILSCALE_HOSTNAME}"
  else
    TUNNEL_URL="http://${TAILSCALE_HOSTNAME}"
  fi

  echo "$TUNNEL_URL" > /tmp/tunnel-url
}

start_tailscale_ssh_tunnel() {
  if [ "$TAILSCALE_FUNNEL" = "true" ]; then
    echo "Starting Tailscale Funnel for SSH..."
    sudo tailscale funnel --bg tcp://22 2>&1 || {
      echo "Warning: Tailscale SSH Funnel failed (non-fatal)"
    }
  fi
  # When not using Funnel, SSH is reachable directly via the tailnet hostname
}

# ============================================================================
# Provider dispatch
# ============================================================================
TUNNEL_URL=""

case "$TUNNEL_PROVIDER" in
  cloudflared)
    if setup_cloudflared; then
      if ! start_cloudflared_tunnel; then
        echo "Falling back to localhost."
        TUNNEL_URL="http://localhost:$TUNNEL_PORT"
      fi
    else
      echo "Cloudflared unavailable, falling back to localhost."
      TUNNEL_URL="http://localhost:$TUNNEL_PORT"
    fi
    ;;

  tailscale)
    if setup_tailscale; then
      start_tailscale_tunnel
    else
      echo "Tailscale unavailable, falling back to localhost."
      TUNNEL_URL="http://localhost:$TUNNEL_PORT"
    fi
    ;;

  both)
    CFD_READY=false
    TS_READY=false

    if setup_cloudflared; then
      if start_cloudflared_tunnel; then
        CFD_READY=true
      fi
    fi

    if setup_tailscale; then
      TS_READY=true
      TAILSCALE_HOSTNAME=$(get_tailscale_hostname)

      if [ "$TAILSCALE_FUNNEL" = "true" ]; then
        sudo tailscale funnel --bg "http://localhost:$TUNNEL_PORT" 2>&1 || true
        echo "Tailscale Funnel URL: https://${TAILSCALE_HOSTNAME}" > /tmp/tailscale-url
      else
        echo "Tailscale URL: http://${TAILSCALE_HOSTNAME}" > /tmp/tailscale-url
      fi
    fi

    # Primary URL: prefer cloudflared (more reliable for browser access)
    if [ "$CFD_READY" = "true" ] && [ -n "$TUNNEL_URL" ]; then
      echo ""
      echo "Tailscale URL (private): http://${TAILSCALE_HOSTNAME:-<not connected>}"
    elif [ "$TS_READY" = "true" ]; then
      # Tailscale-only fallback
      TUNNEL_URL=$(grep -oP 'https?://[a-zA-Z0-9.-]+\.ts\.net' /tmp/tailscale-url 2>/dev/null | head -1 || \
                    grep -oP 'http://[a-zA-Z0-9.-]+\.ts\.net' /tmp/tailscale-url 2>/dev/null | head -1 || true)
    else
      TUNNEL_URL="http://localhost:$TUNNEL_PORT"
    fi
    ;;

  *)
    echo "Unknown tunnel-provider: $TUNNEL_PROVIDER (falling back to cloudflared)"
    if setup_cloudflared && start_cloudflared_tunnel; then
      : # TUNNEL_URL set by start_cloudflared_tunnel
    else
      TUNNEL_URL="http://localhost:$TUNNEL_PORT"
    fi
    ;;
esac

# --- Set TUNNEL_URL env ---
if [ -z "$TUNNEL_URL" ]; then
  echo "Warning: No tunnel URL available, falling back to localhost."
  TUNNEL_URL="http://localhost:$TUNNEL_PORT"
fi
echo "TUNNEL_URL=$TUNNEL_URL" >> "$GITHUB_ENV"
echo "$TUNNEL_URL" > /tmp/tunnel-url

# --- Discord notification ---
DISCORD_WEBHOOK="$DISCORD_WEBHOOK" \
  bash "$SCRIPT_DIR/discord-notify.sh" \
  "💻 **VS Code IDE started**\nURL: ${TUNNEL_URL}/?tkn=${CONNECTION_TOKEN}\nFile Browser: ${TUNNEL_URL}/files/?tkn=${CONNECTION_TOKEN}"

# --- Optional SSH access ---
if [ "$ENABLE_SSH" = "true" ]; then
  echo ""
  echo "Setting up SSH access..."

  case "$TUNNEL_PROVIDER" in
    cloudflared)
      # Traditional SSH: generate keypair, start sshd, cloudflared TCP tunnel
      echo "Using cloudflared TCP tunnel for SSH..."

      SSH_KEY_FILE=/tmp/ssh-key
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q

      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      cat "$SSH_KEY_FILE.pub" >> ~/.ssh/authorized_keys
      chmod 600 ~/.ssh/authorized_keys

      sudo systemctl start sshd 2>/dev/null || sudo service ssh start 2>/dev/null || true

      if [ -x /tmp/cloudflared ]; then
        start_cloudflared_ssh_tunnel
        SSH_URL=$(cat /tmp/ssh-tunnel-url 2>/dev/null || true)
        echo "SSH_URL=$SSH_URL" >> "$GITHUB_ENV"
      else
        echo "Warning: cloudflared not available for SSH tunnel"
      fi
      ;;

    tailscale)
      # Tailscale SSH: built-in, uses Tailscale identity for auth (no keys needed)
      # (tailscale set --ssh already ran in setup_tailscale)
      TAILSCALE_HOSTNAME=$(get_tailscale_hostname)
      echo "Using Tailscale built-in SSH (auth via Tailscale identity)..."
      echo "Connect: ssh $(whoami)@${TAILSCALE_HOSTNAME}"
      echo ""
      echo "Note: Ensure 'SSH' is enabled in your Tailscale ACLs for this node."
      echo "See: https://tailscale.com/kb/1193/acls/#ssh-access"
      ;;

    both)
      # Both: traditional SSH via cloudflared + Tailscale SSH
      echo "Using both cloudflared TCP tunnel + Tailscale built-in SSH..."

      # Traditional SSH keypair + sshd (for cloudflared path)
      SSH_KEY_FILE=/tmp/ssh-key
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q

      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      cat "$SSH_KEY_FILE.pub" >> ~/.ssh/authorized_keys
      chmod 600 ~/.ssh/authorized_keys

      sudo systemctl start sshd 2>/dev/null || sudo service ssh start 2>/dev/null || true

      # Cloudflare TCP tunnel for SSH
      if [ -x /tmp/cloudflared ]; then
        start_cloudflared_ssh_tunnel
        SSH_URL=$(cat /tmp/ssh-tunnel-url 2>/dev/null || true)
        echo "SSH_URL=$SSH_URL" >> "$GITHUB_ENV"
      fi

      # Tailscale SSH (built-in, tailscale set --ssh already ran in setup_tailscale)
      TAILSCALE_HOSTNAME=$(get_tailscale_hostname)
      echo "Tailscale SSH: ssh $(whoami)@${TAILSCALE_HOSTNAME}"
      echo ""
      echo "Note: Ensure 'SSH' is enabled in your Tailscale ACLs for this node."
      ;;
  esac

  # Discord notification for SSH
  DISCORD_WEBHOOK="$DISCORD_WEBHOOK" \
    bash "$SCRIPT_DIR/discord-notify.sh" \
    "🔑 **SSH enabled**\nProvider: ${TUNNEL_PROVIDER}"
fi

echo "::endgroup::"
