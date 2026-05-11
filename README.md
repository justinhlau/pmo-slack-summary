# Slack Daily Summarizer

Local pipeline that exports the previous business day's messages from a fixed list of Slack channels, runs them through Claude, and produces a styled HTML summary.

Repo: https://github.com/justinhlau/pmo-slack-summary · License: MIT

End-to-end runtime is ~30–40s for ~8 channels with light traffic.

---

## Quick start

```bash
# 1. (one-time) populate the channel list
$EDITOR ~/slack-summary/channels.txt

# 2. run whenever you want a fresh summary
~/slack-summary/run.sh
```

Output:
- `~/slack-summary/summaries/<previous-business-day>.html` — open in your browser
- `~/slack-summary/summaries/<previous-business-day>.md` — same content as markdown

---

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| macOS | the script uses BSD `date` flags and `~/Library` paths | — |
| Homebrew | package manager used by the installer | https://brew.sh |
| `slackdump` | exports Slack messages to a local archive | installed by `install.sh` |
| `claude` (Claude Code CLI) | runs the summarization prompt headlessly | installed by `install.sh` |
| `cmark-gfm` | converts markdown summary → HTML | installed by `install.sh` |

`run.sh` also relies on a running **Slackdump MCP server** on `127.0.0.1:8483`. The script auto-launches one if the port isn't already listening (logs to `mcp-server.log`).

### One-time setup (run via `install.sh`)

```bash
./install.sh
```

Idempotent — safe to re-run. It installs the three binaries (skipping anything already present) and registers the Slackdump MCP server with Claude Code at user scope.

Two auth flows still need to happen interactively (each only once):

```bash
# 1. Slackdump → your Slack workspace (browser flow)
slackdump workspace new <workspace-slug>   # e.g. for https://lambda.slack.com → 'lambda'

# 2. Claude Code → your Anthropic account (browser flow)
claude   # log in then exit
```

Credentials are cached at `~/Library/Caches/slackdump/<workspace>.bin` and `~/.claude/` respectively. Re-run the relevant command if you ever see auth errors.

---

## Configuration

### `channels.txt`

One channel per line. Lines starting with `#` and blank lines are ignored. Inline `# comments` after a value are stripped.

Either format works — both resolve to the same channel ID:

```
# Bare ID
C0ASB8DBKMJ

# Full Slack URL (anything after "/archives/" is extracted)
https://lambda.slack.com/archives/C09L3A93E4X
https://lambda.slack.com/archives/C0A3WHSCXN0/p1778277063997589   # thread permalink also fine

C0ATRQRNYL8  # inline comment is stripped
```

This is the **only** file you need to edit during regular use.

### `prompt.md`

The summarization prompt template. Edit if you want to change what gets extracted or how the output is formatted. Placeholders `{{AFTER_TS}}`, `{{END_TS}}`, `{{PREV_DATE}}`, `{{CHANNELS}}`, `{{DUMP_ZIP}}` are filled in by `run.sh`.

---

## Usage

### Normal run

```bash
~/slack-summary/run.sh
```

Pipeline:
1. Compute the previous business day in the user's local timezone
2. `slackdump export` for that day's messages from all channels in `channels.txt`
3. Ensure the Slackdump MCP server is running (auto-launch if not)
4. `claude -p` summarizes via the MCP tools — emits markdown
5. `cmark-gfm` renders the markdown to a styled, self-contained HTML page

### Dry run

```bash
~/slack-summary/run.sh --dry-run
```

Shows resolved binaries, computed date window, the rendered prompt, and the output paths — without running slackdump or claude.

### Environment overrides

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_BIN` | `~/.local/bin/claude` (etc.) | Path to the `claude` binary |
| `SLACKDUMP_BIN` | `/opt/homebrew/bin/slackdump` (etc.) | Path to the `slackdump` binary |
| `CMARK_BIN` | `/opt/homebrew/bin/cmark-gfm` (etc.) | Path to `cmark-gfm` |

---

## Output

### Files written each run

```
~/slack-summary/
├── dumps/<YYYY-MM-DD>.zip      # the day's Slack export
└── summaries/
    ├── <YYYY-MM-DD>.md         # markdown summary
    └── <YYYY-MM-DD>.html       # styled, browser-ready summary
```

`<YYYY-MM-DD>` is the previous business day's UTC date.

Each run overwrites the same-dated files. Older dates are left alone — cull manually if disk usage matters (~1 MB/day typical).

### Output structure

```
# Slack summary — <date>

## #channel-1-name
One-sentence overview.

### <sub-thread topic>
- Initiated by: <name>
- Most active: <names>
- <key points, decisions, updates>

(more sub-threads, then:)

**Action items**
- [#channel-1-name] [Owner] Action — due <date>
- ...

**References**
- [Link label](url) — context
- `PROJ-1234` — context

## #channel-2-name
...

## Quiet channels
- #channel-x-name — no messages in window
- ...

# Consolidated action items
- (every action item from every channel, one scannable list)
```

---

## Analysis parameters

### Time window

The window is **00:00:00 → 23:59:59 UTC of the previous business day** (Mon–Fri).

| Today (local DOW) | Looks back at |
|---|---|
| Mon | Fri |
| Tue–Fri | previous calendar day |
| Sat | Fri |
| Sun | Fri |

Computed by `run.sh` in shell before invoking slackdump, then passed into the prompt as `{{AFTER_TS}}` / `{{END_TS}}` (Unix timestamps).

### What gets extracted per channel

The prompt instructs Claude to:

1. **Sub-thread breakdown** — split the day into discrete topics (each parent message + replies = one sub-thread; substantial standalone messages count too; trivial standalone messages get aggregated into one `Other` group).
2. For each sub-thread, capture:
   - **Initiator** — who started it
   - **Most active** — 2–4 names who drove the discussion
   - **Discussion** — key points, decisions, updates, with specifics (numbers, host/system names, dates)
3. **Action items** — each prefixed with the channel name, plus owner (resolved to display name when possible) and follow-up date if stated
4. **References** — Jira tickets, doc URLs, GitHub PRs, FastTrack/ECX tickets, runbooks, with one-line context each
5. **Name resolution** — `list_users` is called to map Slack user IDs to display names throughout
6. **Channels with no activity** — listed under `Quiet channels` at the end
7. **Consolidated list** — every action item from every channel is re-listed at the very bottom for one scannable view

### Slackdump export options

`run.sh` calls `slackdump export` with:

- `-time-from` / `-time-to` — the computed UTC window
- `-files=false` — skip file attachment downloads (much faster, smaller zips)
- `-channel-users` — bundle only users referenced in the dumped channels (smaller `users.json`)
- `-y` — non-interactive

The output is a Slack-export-format zip containing `users.json`, `channels.json`, and per-channel JSON files. The MCP server's `load_source` opens this directly.

### Claude run options

`run.sh` invokes `claude` with:

- `--print` — headless single-prompt mode
- `--output-format text` — plain text (markdown) to stdout
- `--allowedTools` — limited to the slackdump MCP tools (`load_source`, `list_channels`, `list_users`, `get_messages`, `get_thread`, `get_channel`) so no permission prompts fire

The current working directory is set to `$HOME` before invocation so Claude resolves the project-scoped `local-mcp` server from `~/.claude.json`.

---

## Architecture

```
channels.txt ──┐
               ▼
       run.sh computes the UTC date window
               │
               ▼
   slackdump export ──► dumps/<date>.zip
               │
               ▼
   ensure_mcp_server (auto-launch if needed)
               │
               ▼  HTTP on 127.0.0.1:8483
   claude -p ─── load_source(dumps/<date>.zip)
               ├─ list_users
               ├─ get_messages (per channel)
               └─ get_thread (per parent message)
               │
               ▼
   markdown stdout ──► summaries/<date>.md
               │
               ▼
   cmark-gfm + HTML wrapper ──► summaries/<date>.html
```

The MCP server is started without an archive argument — Claude calls `load_source` to point it at the day's fresh zip on each run, so the server can be long-lived across runs and across other Slackdump uses.

---

## Troubleshooting

### "claude not found" / "slackdump not found"

The non-interactive shell `run.sh` runs in may not have your normal `PATH`. Override:

```bash
CLAUDE_BIN=/path/to/claude SLACKDUMP_BIN=/path/to/slackdump ~/slack-summary/run.sh
```

### "MCP server didn't come up within 10s"

Tail `~/slack-summary/mcp-server.log` for the error. Common causes:
- Port 8483 in use by something other than slackdump → kill it or change `MCP_PORT` in `run.sh`
- slackdump binary missing — `brew install slackdump`

### Slackdump auth errors

```
slackdump workspace list                  # see current workspaces
slackdump workspace new <workspace>       # re-auth (opens browser)
```

### User IDs aren't resolving to names

Verify `users.json` is in the dump zip:

```bash
unzip -l ~/slack-summary/dumps/<date>.zip | grep users.json
```

Should show a few KB of data. If missing, check that `slackdump export` (not `dump`) is being used in `run.sh`.

### Output got wrapped in a `\`\`\`` code fence

The model occasionally ignores the "do not wrap in a code fence" instruction. Re-run usually fixes it. If persistent, tighten the wording in `prompt.md`.

### HTML doesn't render links

URLs need to be in markdown link syntax `[label](url)`, not in backticks. The prompt asks for this — if it still happens, re-run or tweak the prompt.

---

## Sharing with teammates

This repo lives at **https://github.com/justinhlau/pmo-slack-summary**.

Everything in it (except `dumps/`, `summaries/`, `mcp-server.log`, and `channels.txt`) is portable and identical between users — same prompt, same script, same install steps. The `.gitignore` excludes the per-user artifacts.

Teammates clone and install:

```bash
git clone https://github.com/justinhlau/pmo-slack-summary.git ~/slack-summary
cd ~/slack-summary
./install.sh
```

`install.sh` will:
1. Detect macOS + Homebrew (and stop with a clear error if either is missing)
2. Install `slackdump`, `cmark-gfm`, and the Claude Code CLI — skipping any already present
3. Register the `local-mcp` HTTP MCP server with Claude Code at user scope (so it works regardless of which directory `claude` is invoked from)
4. Create `dumps/` and `summaries/` directories
5. Copy `channels.txt.example` → `channels.txt` if the user doesn't have one yet
6. Print the two interactive auth steps remaining (Slackdump workspace + Claude Code login)

The clone can live anywhere — `run.sh` resolves its own directory at runtime, so paths aren't pinned to `~/slack-summary/`.

### What teammates need to do, end to end

```bash
# 1. clone + install
git clone https://github.com/justinhlau/pmo-slack-summary.git ~/slack-summary
cd ~/slack-summary
./install.sh

# 2. one-time auths
slackdump workspace new <workspace-slug>     # e.g. 'lambda'
claude                                        # log in once, then exit

# 3. populate their own channels
$EDITOR channels.txt

# 4. run it
./run.sh
```

### What they need to have

- macOS (Apple Silicon or Intel)
- Homebrew
- A Slack account with access to the channels they want to summarize
- A Claude Code subscription / API access

### What teammates do **not** need to share with you

- Their `channels.txt` (per-user, gitignored)
- Their Slack creds (cached locally in `~/Library/Caches/slackdump/`)
- Their Claude Code login (cached locally in `~/.claude/`)

---

## File reference

| Path | Purpose |
|---|---|
| `run.sh` | Main entry point |
| `install.sh` | One-time installer (idempotent) |
| `prompt.md` | Summarization prompt template |
| `channels.txt.example` | Template — copied to `channels.txt` on first install |
| `channels.txt` | Per-user channel list (gitignored) |
| `dumps/<date>.zip` | Slackdump export, one per run (gitignored) |
| `summaries/<date>.md` | Markdown summary (gitignored) |
| `summaries/<date>.html` | Styled HTML summary (gitignored) |
| `mcp-server.log` | Log file from any auto-launched MCP server (gitignored) |
| `.gitignore` | Excludes generated/personal files |
| `LICENSE` | MIT license |
| `~/Library/Caches/slackdump/<workspace>.bin` | Cached Slackdump auth credentials |
| `~/.claude.json` | Claude Code config — must contain the `local-mcp` HTTP entry (added by `install.sh`) |

---

## License

[MIT](LICENSE) — see the `LICENSE` file.
