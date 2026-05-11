#!/usr/bin/env bash
# Slack Daily Summarizer — installer.
# Idempotent: safe to re-run.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m  %s\n' "$*" >&2; }
err()  { printf '\033[1;31m✗\033[0m  %s\n' "$*" >&2; }

# ---------- 1. Platform check ----------
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "This installer targets macOS only (slackdump install path, BSD date flags, and ~/Library paths assume macOS)."
  err "To run on Linux/WSL you'd need to adapt run.sh manually."
  exit 1
fi
ok "macOS detected"

# ---------- 2. Homebrew ----------
if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew not found. Install it first:"
  err '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  err "Then re-run this installer."
  exit 1
fi
ok "Homebrew found at $(command -v brew)"

# ---------- 3. slackdump ----------
if command -v slackdump >/dev/null 2>&1; then
  ok "slackdump already installed at $(command -v slackdump)"
else
  note "Installing slackdump via Homebrew..."
  brew install slackdump
  ok "slackdump installed"
fi

# ---------- 4. cmark-gfm ----------
if command -v cmark-gfm >/dev/null 2>&1; then
  ok "cmark-gfm already installed at $(command -v cmark-gfm)"
else
  note "Installing cmark-gfm via Homebrew..."
  brew install cmark-gfm
  ok "cmark-gfm installed"
fi

# ---------- 5. Claude Code CLI ----------
CLAUDE_BIN=""
if command -v claude >/dev/null 2>&1; then
  CLAUDE_BIN=$(command -v claude)
elif [ -x "$HOME/.local/bin/claude" ]; then
  CLAUDE_BIN="$HOME/.local/bin/claude"
fi

if [ -n "$CLAUDE_BIN" ]; then
  ok "Claude Code CLI already installed at $CLAUDE_BIN"
else
  note "Installing Claude Code CLI from claude.ai..."
  curl -fsSL https://claude.ai/install.sh | bash
  CLAUDE_BIN="$HOME/.local/bin/claude"
  if [ ! -x "$CLAUDE_BIN" ]; then
    err "Claude Code install reported success but binary not found at $CLAUDE_BIN"
    exit 1
  fi
  ok "Claude Code CLI installed at $CLAUDE_BIN"
fi

# ---------- 6. Register the local Slackdump MCP server with Claude Code ----------
if "$CLAUDE_BIN" mcp list 2>/dev/null | grep -qiE "^local-mcp:|claude\.ai .*local-mcp"; then
  ok "MCP server 'local-mcp' already registered with Claude Code"
else
  note "Registering 'local-mcp' MCP server (user scope, HTTP transport)..."
  "$CLAUDE_BIN" mcp add --scope user --transport http local-mcp http://127.0.0.1:8483/mcp
  ok "MCP server registered"
fi

# ---------- 7. Working directory ----------
mkdir -p "$DIR/dumps" "$DIR/summaries"
[ -x "$DIR/run.sh" ] || chmod +x "$DIR/run.sh"

# Seed channels.txt from the template if the user doesn't have one yet.
if [ ! -f "$DIR/channels.txt" ] && [ -f "$DIR/channels.txt.example" ]; then
  cp "$DIR/channels.txt.example" "$DIR/channels.txt"
  ok "Created $DIR/channels.txt from template (edit it to add your channels)"
else
  ok "Working directory ready: $DIR"
fi

# ---------- 8. Next steps ----------
cat <<EOF

$(note "Install complete.")

Two manual auth flows are still needed (each only once):

  1. Slackdump → your Slack workspace (browser flow):
       slackdump workspace new <workspace-slug>
     The slug is the part before .slack.com in your workspace URL.
     For example, https://lambda.slack.com → slug is 'lambda':
       slackdump workspace new lambda

  2. Claude Code → your Anthropic account (browser flow):
       $CLAUDE_BIN
     This drops you into a Claude session; you can exit immediately
     once you've completed the browser auth.

After that:
  3. Populate $DIR/channels.txt with the channels you want summarized
     (one channel ID or Slack URL per line — see comments in the file).
  4. Run it:
       $DIR/run.sh

Full docs: $DIR/README.md
EOF
