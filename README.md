# vsweb — VS Code Web IDE on GitHub Actions

Run a full VS Code Web IDE on a GitHub Actions runner, accessible from any browser. Workspace persists across sessions via artifacts.

## Quick Start

1. Copy `.github/workflows/ide.yml` to your repo's `.github/workflows/` directory
2. Copy the `scripts/` folder to your repo
3. Go to your repo's Actions tab → **VS Code Web IDE** → **Run workflow**
4. Wait ~30s, then open the URL printed in the logs

```
https://<random>.trycloudflare.com/?tkn=<token>
```

## What You Get

| Service | URL Path | Description |
|---------|----------|-------------|
| VS Code IDE | `/` | Full VS Code in browser (same engine as Codespaces) |
| File Browser | `/files/` | Dark-themed file explorer, browse & download any file |
| SSH (opt-in) | — | Tunnel for Remote-SSH from desktop VS Code |

## Pre-Installed

- **openvscode-server** — upstream VS Code (same as GitHub Codespaces)
- **Java 21** (Temurin) — `JAVA_HOME` set
- **Android SDK** — `ANDROID_HOME` and `ANDROID_SDK_ROOT` set (pre-installed on Ubuntu runner)
- **OpenCode** — AI coding agent CLI
- **Node.js / Python / Docker / Git** — already on the runner
- **VS Code Extensions** — Copilot, Python, Java Pack, Docker, Prettier (configurable)

## Workflow Inputs

All configurable from the GitHub Actions UI when triggering the workflow:

| Input | Default | Description |
|-------|---------|-------------|
| `session-timeout` | `360` | Max job duration (minutes). 360 max for GitHub-hosted runners. |
| `inactivity-timeout` | `20` | Minutes of no browser connections before shutdown warning. |
| `extensions` | `GitHub.copilot,...` | Comma-separated VS Code extension IDs to pre-install. |
| `connection-token` | auto-generated | Auth token for the VS Code web UI. |
| `enable-ssh` | `false` | Also expose SSH via tunnel for Remote-SSH. |
| `dotfiles-uri` | `""` | Git URI of a dotfiles repo to clone and run at startup. |

## Workspace Persistence

- Workspace is **auto-saved every 30 minutes** as a GitHub Actions artifact
- On the **next run**, the previous workspace is automatically restored
- VS Code state (open files, extensions, settings) is also persisted
- Final save runs when you create `/continue` or inactivity timeout fires
- Excluded from snapshot: `.git`, `node_modules`, `build/`, `target/`, `.gradle/`

## Session Lifecycle

```
Trigger workflow
  → Restore workspace from previous artifact
  → Setup tools (Java, OpenCode, Android, dotfiles, init hook)
  → Start openvscode-server + file explorer + tunnel
  → Print access URL
  └── [ACTIVE] ──→  30s heartbeat loop:
                      • Check for continue file (/continue)
                      • Check TCP connections to VS Code port
                      • Monitor remaining job time
                      • Auto-save if idle > timeout
                      • Auto-save every 30 min
                      • Auto-shutdown 5 min before job timeout
  → Save workspace → Upload artifact → Cleanup
```

### Ending a Session

Create the continue file in the IDE terminal:

```bash
touch /continue
```

Or let the inactivity timeout handle it. The warning file `SESSION_INACTIVITY_WARNING.md` appears in your workspace 5 minutes before auto-shutdown.

### init Hook

If your repo has `.github/ide-init.sh`, it runs automatically at startup. Use this to install additional tools, set configs, or clone repos:

```bash
#!/bin/bash
# .github/ide-init.sh
apt-get update && apt-get install -y postgresql-client redis-tools
npm install -g serve
echo "Custom setup complete!"
```

## SSH Access (opt-in)

When `enable-ssh: true`, the workflow:
1. Generates an ed25519 keypair
2. Starts SSHD
3. Creates a separate Cloudflare TCP tunnel for SSH
4. Prints the private key and connection command in logs

Connect from your local VS Code via Remote-SSH:

```bash
# Requires cloudflared on your local machine
ssh -o StrictHostKeyChecking=no -i /path/to/saved-key runner@<tunnel-host> \
  -o ProxyCommand='cloudflared access tcp --hostname %h'
```

## Security

### How Access Works

There are **two secrets** you need to access the IDE:

1. **Tunnel URL** — random string like `https://abc123.trycloudflare.com`
2. **Connection Token** — 64-character hex string, generated per-session

The tunnel URL is printed prominently in the logs. The token is printed separately. You need **both** to access the VS Code IDE.

If you open the URL without the token, VS Code will show a login page asking for it. The token is never embedded in the URL by default — you add `?tkn=TOKEN` yourself for one-click convenience.

### Security Layers

| Layer | What it protects against |
|-------|--------------------------|
| **Random tunnel URL** | Random discovery / scanning bots |
| **Connection token** | Anyone who finds the URL (log viewers, browser history) |
| **Token stored in file** | Not visible in `ps` process listings (`--connection-token-file`) |
| **GitHub Actions auth** | Only users with repo access can see the logs (repo access required) |
| **Ephemeral token** | New token every session, previous tokens don't work |
| **Inactivity auto-shutdown** | Session doesn't stay open if you forget it |

### Threat Scenarios

| Scenario | Risk |
|----------|------|
| Someone finds the tunnel URL | **Can't access** — need the token too |
| Someone finds the token | **Can't access** — need the URL too |
| Someone has repo read access | **Can access** — they can see both in logs. Protect your repo. |
| You bookmark the URL with `?tkn=...` | **Moderate** — browser history leak. Use separate URL + token. |

### For Maximum Security (Cloudflare Access)

If you have a Cloudflare account, you can add **Zero Trust authentication** before the tunnel. This adds a login page (Google, GitHub, email, etc.) before anyone even reaches VS Code:

1. Go to Cloudflare Zero Trust → Access → Applications
2. Create a self-hosted application with your tunnel's hostname
3. Set up a policy (e.g., "only allow your email")
4. Restart the tunnel with `cloudflared tunnel --url ...` — users authenticate via Cloudflare first, then enter the VS Code token

This gives you **three layers**: Cloudflare Access → VS Code token → inactivity timeout.

### SSH Keys

When `enable-ssh: true`, the private key is printed in the action logs. Anyone with repo access can see it. Keys are ephemeral (new every session). For production use, consider Cloudflare Access for SSH instead.

### File Browser

The file explorer at `/files/` provides read-only access to the entire VM filesystem. Only accessible through the tunnel URL and requires the connection token. No upload or delete functionality is exposed.

## Customization Ideas

- Add more `actions/setup-*` steps for Go, Rust, .NET, etc.
- Use `windows-latest` or `macos-latest` runners
- Set up a Cloudflare Zero Trust policy for extra auth
- Use self-hosted runners for sessions longer than 6 hours
- Add a webhook to post the URL to Slack/Discord

## File Structure

```
.github/workflows/ide.yml          # Main workflow (copy to your repo)
scripts/
├── restore-workspace.sh           # Download + extract previous artifact
├── setup-tools.sh                 # OpenCode, Android, dotfiles, init hook
├── start-ide.sh                   # openvscode-server + file-server + tunnel
├── file-server.mjs                # Custom Node.js: reverse proxy + file explorer
├── watch-inactivity.sh            # Connection monitoring + auto-shutdown
└── save-workspace.sh              # Package workspace for artifact upload
```
