---
name: customize-opencode
description: Use ONLY when the user is editing or creating opencode's own configuration: opencode.json, opencode.jsonc, files under .opencode/, or files under ~/.config/opencode/. Also use when creating or fixing opencode agents, subagents, skills, plugins, MCP servers, or permission rules. Do not use for the user's own application code, or for any project that is not configuring opencode itself.
---

# Customizing opencode

opencode validates its own config strictly and refuses to start when a field
is wrong. The shapes below cover the common surface area, but they are a
summary, not the source of truth.

## Full schema reference

The authoritative list of every config option lives in the published JSON Schema:

**<https://opencode.ai/config.json>**

If a field is not documented in this skill, or you need to confirm an exact
shape before writing config, fetch that URL and read the schema directly.

Every `opencode.json` should declare `"$schema": "https://opencode.ai/config.json"`.

## Applying changes

Config is loaded once when opencode starts and is not hot-reloaded. After
saving changes, tell the user to quit and restart opencode.

## Where files live

| Scope       | Path |
| ----------- | ---- |
| Project config | `./opencode.json`, `./opencode.jsonc`, or `.opencode/opencode.json` |
| Global config  | `~/.config/opencode/opencode.json` |
| Project agents | `.opencode/agent/<name>.md` or `.opencode/agents/<name>.md` |
| Global agents  | `~/.config/opencode/agent(s)/<name>.md` |
| Project skills | `.opencode/skill(s)/<name>/SKILL.md` |
| Global skills  | `~/.config/opencode/skill(s)/<name>/SKILL.md` |

## opencode.json shape

```json
{
  "$schema": "https://opencode.ai/config.json",
  "username": "string",
  "model": "provider/model-id",
  "small_model": "provider/model-id",
  "default_agent": "agent-name",
  "shell": "/bin/zsh",
  "logLevel": "DEBUG | INFO | WARN | ERROR",
  "instructions": ["AGENTS.md", "docs/style.md"],
  "skills": {
    "paths": [".opencode/skills", "/abs/path/to/skills"],
    "urls": ["https://example.com/.well-known/skills/"]
  },
  "agent": {
    "my-agent": {
      "model": "anthropic/claude-sonnet-4-6",
      "mode": "subagent",
      "description": "...",
      "permission": { "edit": "deny" }
    }
  },
  "command": {
    "deploy": { "description": "...", "prompt": "..." }
  },
  "plugin": [
    "opencode-gemini-auth",
    "./local-plugin.ts",
    ["opencode-bar", { "option": "value" }]
  ],
  "permission": {
    "edit": "deny",
    "bash": { "git *": "allow", "*": "ask" }
  },
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "-y", "@playwright/mcp"],
      "enabled": true,
      "env": {}
    }
  },
  "provider": {
    "anthropic": { "options": { "apiKey": "..." } }
  },
  "disabled_providers": ["openai"],
  "formatter": false,
  "lsp": false,
  "experimental": {
    "primary_tools": ["edit"],
    "mcp_timeout": 30000
  },
  "compaction": { "auto": true, "tail_turns": 15 }
}
```

## Skills

```
.opencode/skills/my-skill/SKILL.md
```

Frontmatter: `name` (required), `description` (required), `license`, `compatibility`, `metadata`.

Register non-default locations via `skills.paths` and `skills.urls`.

## Agents

Inline in `opencode.json` under `agent: {}`, or as files in `.opencode/agent/<name>.md`.

File frontmatter fields: `name, model, variant, description, mode, hidden, color, steps, options, permission, disable, temperature, top_p`.

## Plugins

Auto-discovered: any `*.ts` or `*.js` in `.opencode/plugin/` or `.opencode/plugins/`.

Explicit: `plugin: ["opencode-foo@1.2.3", "./local-plugin.ts", ["opencode-bar", {}]]`.

## MCP servers

Keyed by name under `mcp: {}`, discriminated by `type`: `local` (with `command: string[]`) or `remote` (with `url` and optional `headers`).

## Permissions

```json
"permission": {
  "edit": "deny",
  "bash": { "git *": "allow", "*": "ask" }
}
```

Actions: `allow`, `ask`, `deny`. Per-tool: string shorthand or `{ pattern: action }`. Last matching rule wins.

## Escape hatches

- `OPENCODE_DISABLE_PROJECT_CONFIG=1`: skip local config
- `OPENCODE_CONFIG=/path/to/file.json`: explicit config
- `OPENCODE_CONFIG_CONTENT='{...}'`: inline JSON merge
- `OPENCODE_DISABLE_DEFAULT_PLUGINS=1`, `OPENCODE_PURE=1`

## Guidelines

- Validate against the schema before writing config.
- Preserve `$schema` and existing fields you are not asked to change.
- Prefer files over inlining in `opencode.json` for agents, skills, and plugins.
- After saving any config change, remind the user to quit and restart opencode.
