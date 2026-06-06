#!/bin/bash
set -e

echo "::group::Setup tools"

# --- OpenCode CLI ---
echo "Installing OpenCode..."
curl -fsSL https://opencode.ai/install | bash 2>/dev/null || {
  echo "OpenCode install script failed, trying npm..."
  npm install -g opencode-ai@latest 2>/dev/null || echo "Warning: OpenCode install failed (non-fatal)"
}

# --- OpenCode config ---
echo "Setting up OpenCode config..."
mkdir -p ~/.config/opencode
if [ -d "$GITHUB_WORKSPACE/.opencode" ]; then
  ln -sf "$GITHUB_WORKSPACE/.opencode" ~/.config/opencode/project
  echo "Linked .opencode to ~/.config/opencode/project"
fi

# --- Android SDK env vars ---
if [ -d /usr/local/lib/android/sdk ]; then
  export ANDROID_HOME=/usr/local/lib/android/sdk
  export ANDROID_SDK_ROOT=/usr/local/lib/android/sdk
  echo "ANDROID_HOME=/usr/local/lib/android/sdk" >> "$GITHUB_ENV"
  echo "ANDROID_SDK_ROOT=/usr/local/lib/android/sdk" >> "$GITHUB_ENV"
  echo "Android SDK found at $ANDROID_HOME"
else
  echo "Warning: Android SDK not pre-installed on this runner"
fi

# --- dotfiles ---
if [ -n "$DOTFILES_URI" ]; then
  echo "Cloning dotfiles from $DOTFILES_URI..."
  DOTFILES_DIR=$(mktemp -d)
  if git clone --depth 1 "$DOTFILES_URI" "$DOTFILES_DIR" 2>/dev/null; then
    if [ -f "$DOTFILES_DIR/install.sh" ]; then
      echo "Running dotfiles install.sh..."
      bash "$DOTFILES_DIR/install.sh" 2>/dev/null || true
    elif [ -f "$DOTFILES_DIR/bootstrap.sh" ]; then
      echo "Running dotfiles bootstrap.sh..."
      bash "$DOTFILES_DIR/bootstrap.sh" 2>/dev/null || true
    fi
    if [ -d "$DOTFILES_DIR/.config" ]; then
      mkdir -p ~/.config
      cp -r "$DOTFILES_DIR/.config/"* ~/.config/ 2>/dev/null || true
    fi
    if [ -f "$DOTFILES_DIR/.gitconfig" ]; then
      cat "$DOTFILES_DIR/.gitconfig" >> ~/.gitconfig 2>/dev/null || true
    fi
    rm -rf "$DOTFILES_DIR"
  else
    echo "Warning: Failed to clone dotfiles repo"
  fi
fi

# --- init hook ---
if [ -f "$GITHUB_WORKSPACE/.github/ide-init.sh" ]; then
  echo "Running .github/ide-init.sh..."
  chmod +x "$GITHUB_WORKSPACE/.github/ide-init.sh"
  bash "$GITHUB_WORKSPACE/.github/ide-init.sh" || echo "Warning: ide-init.sh exited with code $?"
fi

# --- Git config (defaults only, don't overwrite if already set) ---
current_name=$(git config --global user.name 2>/dev/null || true)
current_email=$(git config --global user.email 2>/dev/null || true)
if [ -z "$current_name" ] && [ -n "$GITHUB_ACTOR" ]; then
  git config --global user.name "$GITHUB_ACTOR" 2>/dev/null || true
fi
if [ -z "$current_email" ] && [ -n "$GITHUB_ACTOR" ]; then
  git config --global user.email "$GITHUB_ACTOR@users.noreply.github.com" 2>/dev/null || true
fi
git config --global core.autocrlf input 2>/dev/null || true
git config --global init.defaultBranch main 2>/dev/null || true

echo "::endgroup::"
