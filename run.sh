#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Capture script start time (UTC, Unix seconds). Used as the upper bound of
# the "since last run" window and persisted to .last-run on success.
SCRIPT_START_TS=$(date -u +%s)

# Resolve the directory the script lives in, so this works whether installed
# at ~/slack-summary/ or cloned from a repo to any other path.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$DIR/prompt.md"
CHANNELS_FILE="$DIR/channels.txt"
SUMMARIES_DIR="$DIR/summaries"
DUMPS_DIR="$DIR/dumps"
LAST_RUN_FILE="$DIR/.last-run"
mkdir -p "$SUMMARIES_DIR" "$DUMPS_DIR"

# Locate slackdump binary
SLACKDUMP_BIN="${SLACKDUMP_BIN:-$(command -v slackdump || true)}"
if [ -z "$SLACKDUMP_BIN" ]; then
  for candidate in /opt/homebrew/bin/slackdump /usr/local/bin/slackdump; do
    [ -x "$candidate" ] && SLACKDUMP_BIN="$candidate" && break
  done
fi
if [ -z "$SLACKDUMP_BIN" ]; then
  echo "Error: 'slackdump' not found. Install via: brew install slackdump" >&2
  exit 1
fi

# Locate cmark-gfm (markdown -> HTML); auto-install via Homebrew if missing.
CMARK_BIN="${CMARK_BIN:-$(command -v cmark-gfm || true)}"
if [ -z "$CMARK_BIN" ]; then
  for candidate in /opt/homebrew/bin/cmark-gfm /usr/local/bin/cmark-gfm; do
    [ -x "$candidate" ] && CMARK_BIN="$candidate" && break
  done
fi
if [ -z "$CMARK_BIN" ]; then
  echo "cmark-gfm not found — installing via Homebrew..." >&2
  if ! command -v brew >/dev/null 2>&1; then
    echo "Error: 'brew' not found. Install cmark-gfm manually or set CMARK_BIN." >&2
    exit 1
  fi
  brew install cmark-gfm >&2
  CMARK_BIN=$(command -v cmark-gfm || echo /opt/homebrew/bin/cmark-gfm)
  if [ ! -x "$CMARK_BIN" ]; then
    echo "Error: cmark-gfm install reported success but binary not found." >&2
    exit 1
  fi
fi

MCP_HOST=127.0.0.1
MCP_PORT=8483
MCP_LOG="$DIR/mcp-server.log"

# Check if anything is listening on $MCP_HOST:$MCP_PORT (bash /dev/tcp probe).
mcp_port_open() {
  (echo > "/dev/tcp/$MCP_HOST/$MCP_PORT") >/dev/null 2>&1
}

# Start the slackdump MCP server in the background if it isn't already running.
# Omits the archive arg — the agent will call load_source to point at the day's zip.
ensure_mcp_server() {
  if mcp_port_open; then
    return 0
  fi
  echo "MCP server not running on $MCP_HOST:$MCP_PORT — starting it..." >&2
  : > "$MCP_LOG"
  nohup "$SLACKDUMP_BIN" mcp -transport http -listen "$MCP_HOST:$MCP_PORT" \
    >> "$MCP_LOG" 2>&1 &
  disown
  for _ in $(seq 1 20); do
    sleep 0.5
    if mcp_port_open; then
      echo "MCP server ready (log: $MCP_LOG)" >&2
      return 0
    fi
  done
  echo "Error: MCP server didn't come up within 10s. See $MCP_LOG" >&2
  exit 1
}

# Locate claude binary (override with CLAUDE_BIN=/path/to/claude if needed).
# Skip the desktop app's bundled binary (claude-code-vm) — it's a Linux ELF
# that only runs inside the VM the desktop app spawns.
CLAUDE_BIN="${CLAUDE_BIN:-}"
if [ -z "$CLAUDE_BIN" ]; then
  for candidate in \
    "$HOME/.local/bin/claude" \
    "$HOME/.claude/local/claude" \
    "$HOME/.npm-global/bin/claude" \
    "/opt/homebrew/bin/claude" \
    "/usr/local/bin/claude"; do
    [ -x "$candidate" ] && CLAUDE_BIN="$candidate" && break
  done
fi
if [ -z "$CLAUDE_BIN" ]; then
  CLAUDE_BIN=$(command -v claude || true)
fi
if [ -z "$CLAUDE_BIN" ]; then
  echo "Error: 'claude' not found. Set CLAUDE_BIN to the binary path." >&2
  exit 1
fi

# Previous business day window (00:00:00 -> 23:59:59 UTC)
DOW=$(date +%u)
case "$DOW" in
  1) DAYS_BACK=3 ;;  # Monday  -> Friday
  7) DAYS_BACK=2 ;;  # Sunday  -> Friday
  *) DAYS_BACK=1 ;;  # otherwise -> previous calendar day
esac
PREV_DATE=$(date -v-${DAYS_BACK}d +%Y-%m-%d)
AFTER_TS=$(date -j -u -f "%Y-%m-%d %H:%M:%S" "$PREV_DATE 00:00:00" +%s)
END_TS=$(date -j -u -f "%Y-%m-%d %H:%M:%S" "$PREV_DATE 23:59:59" +%s)

# Today's local date — used for output filenames so each run's report is
# named after the day it was generated.
TODAY=$(date +%Y-%m-%d)

# Since-last-run window (UTC).
# Read .last-run if present and valid (digits only); default to END_TS+1 (end
# of biz-day) so first runs cover "everything since end of yesterday".
# The since-window is always clamped to start at max(LAST_RUN, END_TS+1) so
# it never overlaps with the previous-business-day section.
DEFAULT_LAST_RUN=$(( END_TS + 1 ))
if [ -r "$LAST_RUN_FILE" ] && [[ "$(cat "$LAST_RUN_FILE" 2>/dev/null)" =~ ^[0-9]+$ ]]; then
  LAST_RUN=$(cat "$LAST_RUN_FILE")
else
  LAST_RUN=$DEFAULT_LAST_RUN
fi
if [ "$LAST_RUN" -gt "$DEFAULT_LAST_RUN" ]; then
  SINCE_AFTER_TS=$LAST_RUN
else
  SINCE_AFTER_TS=$DEFAULT_LAST_RUN
fi
SINCE_BEFORE_TS=$SCRIPT_START_TS
# Clamp pathological case where SINCE_BEFORE_TS < SINCE_AFTER_TS (e.g. clock skew).
if [ "$SINCE_BEFORE_TS" -lt "$SINCE_AFTER_TS" ]; then
  SINCE_BEFORE_TS=$SINCE_AFTER_TS
fi
SINCE_FROM_HUMAN=$(date -u -r "$SINCE_AFTER_TS" +"%Y-%m-%d %H:%M:%S UTC")
SINCE_TO_HUMAN=$(date -u -r "$SINCE_BEFORE_TS" +"%Y-%m-%d %H:%M:%S UTC")
DUMP_TIME_TO=$(date -u -r "$SINCE_BEFORE_TS" +"%Y-%m-%dT%H:%M:%S")

# Read channels. Skip blanks/comments, strip inline comments, and accept
# either bare IDs (C09MYP5K4H4) or full Slack URLs
# (https://workspace.slack.com/archives/C09MYP5K4H4[/p123...][?query]) —
# normalize to just the channel ID.
CHANNELS=$(grep -vE '^[[:space:]]*(#|$)' "$CHANNELS_FILE" \
  | sed -E 's|[[:space:]]*#.*$||; s|^[[:space:]]+||; s|^.*/archives/||; s|[/?].*$||; s|[[:space:]]+$||' \
  | grep -v '^$' || true)
CHANNEL_COUNT=$(printf '%s\n' "$CHANNELS" | grep -c . || true)
if [ -z "$CHANNELS" ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "Error: $CHANNELS_FILE has no channel IDs. Add one ID per line." >&2
  exit 1
fi

DUMP_ZIP="$DUMPS_DIR/$TODAY.zip"
OUT="$SUMMARIES_DIR/$TODAY.md"
HTML_OUT="$SUMMARIES_DIR/$TODAY.html"

# Substitute placeholders into the prompt
PROMPT=$(cat "$PROMPT_FILE")
PROMPT=${PROMPT//\{\{AFTER_TS\}\}/$AFTER_TS}
PROMPT=${PROMPT//\{\{END_TS\}\}/$END_TS}
PROMPT=${PROMPT//\{\{PREV_DATE\}\}/$PREV_DATE}
PROMPT=${PROMPT//\{\{CHANNELS\}\}/$CHANNELS}
PROMPT=${PROMPT//\{\{DUMP_ZIP\}\}/$DUMP_ZIP}
PROMPT=${PROMPT//\{\{SINCE_AFTER_TS\}\}/$SINCE_AFTER_TS}
PROMPT=${PROMPT//\{\{SINCE_BEFORE_TS\}\}/$SINCE_BEFORE_TS}
PROMPT=${PROMPT//\{\{SINCE_FROM_HUMAN\}\}/$SINCE_FROM_HUMAN}
PROMPT=${PROMPT//\{\{SINCE_TO_HUMAN\}\}/$SINCE_TO_HUMAN}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "=== DRY RUN ==="
  echo "claude binary     : $CLAUDE_BIN"
  echo "slackdump binary  : $SLACKDUMP_BIN"
  echo "cmark-gfm binary  : $CMARK_BIN"
  echo "today (local)     : $TODAY"
  echo "prev biz date     : $PREV_DATE  (DOW today=$DOW, days back=$DAYS_BACK)"
  echo "biz-day window    : $AFTER_TS .. $END_TS"
  echo "                    ($PREV_DATE 00:00:00 UTC .. 23:59:59 UTC)"
  echo "state file        : $LAST_RUN_FILE ($([ -f "$LAST_RUN_FILE" ] && cat "$LAST_RUN_FILE" || echo 'absent — first run'))"
  echo "since-last-run    : $SINCE_AFTER_TS .. $SINCE_BEFORE_TS"
  echo "                    ($SINCE_FROM_HUMAN .. $SINCE_TO_HUMAN)"
  echo "channels file     : $CHANNELS_FILE ($CHANNEL_COUNT id(s))"
  echo "dump zip          : $DUMP_ZIP"
  echo "dump window       : ${PREV_DATE}T00:00:00 .. $DUMP_TIME_TO  (UTC)"
  echo "summary out (md)  : $OUT"
  echo "summary out (html): $HTML_OUT"
  echo "--- rendered prompt ---"
  printf '%s\n' "$PROMPT"
  echo "--- end ---"
  exit 0
fi

# Step 1: dump messages covering both windows (biz day + since-last-run)
# into a single zip. Use `export` (Slack-export format with users.json
# bundled) so the MCP server can resolve user IDs to display names.
echo "Dumping ${PREV_DATE}T00:00:00 .. $DUMP_TIME_TO UTC for $CHANNEL_COUNT channel(s) -> $DUMP_ZIP" >&2
rm -rf "$DUMP_ZIP" "${DUMP_ZIP%.zip}"
# shellcheck disable=SC2086 -- $CHANNELS is intentionally word-split into channel-id args
"$SLACKDUMP_BIN" export \
  -time-from "${PREV_DATE}T00:00:00" \
  -time-to "$DUMP_TIME_TO" \
  -files=false \
  -channel-users \
  -y \
  -o "$DUMP_ZIP" \
  $CHANNELS

# Step 2: make sure the MCP server is up (start it if not).
ensure_mcp_server

# Step 3: summarize via claude. The prompt instructs it to call
# load_source first so the MCP server points at the fresh dump.
# The local-mcp server is registered under the project /Users/justin.lau,
# so cd there before invoking claude headlessly.
echo "Summarizing -> $OUT" >&2
cd "$HOME"
"$CLAUDE_BIN" \
  --print "$PROMPT" \
  --allowedTools "mcp__local-mcp__load_source,mcp__local-mcp__list_channels,mcp__local-mcp__list_users,mcp__local-mcp__get_messages,mcp__local-mcp__get_thread,mcp__local-mcp__get_channel" \
  --output-format text \
  < /dev/null \
  > "$OUT"

# Step 4: render the markdown to a self-contained HTML page.
echo "Rendering HTML -> $HTML_OUT" >&2
{
  cat <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Slack summary — $TODAY</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
         max-width: 860px; margin: 2rem auto; padding: 0 1.25rem; line-height: 1.55;
         color: #1a1a1a; background: #fafafa; }
  h1 { border-bottom: 2px solid #ddd; padding-bottom: 0.3em; margin-top: 1.5em; }
  h2 { border-bottom: 1px solid #ddd; padding-bottom: 0.2em; margin-top: 2.25em; }
  h3 { margin-top: 1.75em; color: #333; }
  p, ul, ol { margin: 0.5em 0; }
  ul { padding-left: 1.5em; }
  li { margin: 0.2em 0; }
  code { background: #eef0f3; padding: 0.1em 0.35em; border-radius: 3px;
         font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em; }
  pre { background: #eef0f3; padding: 1em; overflow-x: auto; border-radius: 4px; }
  pre code { background: none; padding: 0; }
  a { color: #0366d6; text-decoration: none; }
  a:hover { text-decoration: underline; }
  strong { color: #000; }
  blockquote { border-left: 3px solid #ddd; margin: 0.5em 0; padding: 0 1em; color: #555; }
</style>
</head>
<body>
HTML_HEAD
  "$CMARK_BIN" --extension autolink --extension strikethrough --extension table "$OUT"
  echo "</body></html>"
} > "$HTML_OUT"

# Step 5: persist the script-start timestamp so the next run's since-window
# starts here. Atomic write — only advance the marker on full success.
printf '%s\n' "$SCRIPT_START_TS" > "$LAST_RUN_FILE.tmp"
mv "$LAST_RUN_FILE.tmp" "$LAST_RUN_FILE"

echo "Done: $OUT" >&2
echo "      $HTML_OUT" >&2
echo "      .last-run advanced to $SCRIPT_START_TS" >&2
