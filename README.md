# Slack Daily Summarizer

Local pipeline that exports messages from a fixed list of Slack channels and runs them through Claude to produce two styled HTML reports in one shot:

1. **Previous business day** — the full day, Mon–Fri logic (Mon→Fri, Sat/Sun→Fri, etc.)
2. **Since last run** — everything from when the script previously completed up to now (deduped against window 1)

Repo: https://github.com/justinhlau/pmo-slack-summary · License: MIT

End-to-end runtime is ~30–60s for ~8 channels with light traffic.

---

## Quick start

```bash
# 1. clone + install (one-time)
git clone https://github.com/justinhlau/pmo-slack-summary.git ~/slack-summary
cd ~/slack-summary
./install.sh

# 2. one-time auth flows (each opens a browser)
slackdump workspace new <workspace-slug>   # e.g. 'lambda' for https://lambda.slack.com
claude                                      # log in then exit

# 3. add the channels you want summarized
$EDITOR channels.txt

# 4. run it (and any day after)
./run.sh
```

`install.sh` is idempotent — it installs `slackdump`, `cmark-gfm`, and the Claude Code CLI (skipping any already present), registers the Slackdump MCP server with Claude Code at user scope, and seeds `channels.txt` from the template. The clone can live anywhere — `run.sh` resolves its own directory at runtime, so paths aren't pinned to `~/slack-summary/`.

Output (named after the day the report was generated, not the day being summarized):
- `summaries/<today>.html` — open in your browser
- `summaries/<today>.md` — same content as markdown

### What each user keeps local (gitignored)

`channels.txt`, `dumps/`, `summaries/`, `.last-run`, `mcp-server.log`. Cloning the repo gives you the script and prompt — never anyone else's channel list, reports, or run history. Slack auth caches at `~/Library/Caches/slackdump/<workspace>.bin`; Claude auth caches at `~/.claude/`.

---

## Prerequisites

| Tool | Why | Install |
|---|---|---|
| macOS | the script uses BSD `date` flags and `~/Library` paths | — |
| Homebrew | package manager used by the installer | https://brew.sh |
| `slackdump` | exports Slack messages to a local archive | installed by `install.sh` |
| `claude` (Claude Code CLI) | runs the summarization prompt headlessly | installed by `install.sh` |
| `cmark-gfm` | converts markdown summary → HTML | installed by `install.sh` |
| A Slack account | with access to the channels you want summarized | — |
| A Claude Code subscription / API access | for the summarization model | — |

`run.sh` also relies on a running **Slackdump MCP server** on `127.0.0.1:8483`. The script auto-launches one if the port isn't already listening (logs to `mcp-server.log`).

Re-run `slackdump workspace new <workspace>` or `claude` (then exit) if you ever see auth errors — credentials are cached at `~/Library/Caches/slackdump/<workspace>.bin` and `~/.claude/` respectively.

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
├── dumps/<TODAY>.zip            # Slack export spanning both windows
├── summaries/
│   ├── <TODAY>.md               # markdown report
│   └── <TODAY>.html             # styled, browser-ready report
└── .last-run                    # UTC Unix timestamp of last successful run
```

`<TODAY>` is the local date the script was run on. Re-running the same day overwrites — cull manually if disk usage matters (~1 MB/day typical).

`.last-run` is written atomically only after the HTML render succeeds, so failed runs don't advance the marker and re-runs re-cover the same window.

### Output structure

Each report has two top-level windows plus a consolidated action-items list:

```
# Previous business day — <PREV_DATE>

## #channel-1-name
One-sentence overview of that day's activity in the channel.

### <sub-thread topic>
- Initiated by: <name>
- Most active: <names>
- <key points, decisions, updates>

(more sub-threads, then:)

**Action items**
- [#channel-1-name] [Owner] Action — due <date>

**References**
- [Link label](url) — context
- `PROJ-1234` — context

## #channel-2-name
...

## Quiet channels
- `#channel-x-name` — no messages in window


# Since last run — <FROM-UTC> → <TO-UTC>

(Same per-channel structure as above, filtered to the since-last-run window.
If empty: `_No new messages since last run._`)


# Consolidated action items

## From previous business day
- [#channel] [Owner] Action — due <date>
- ...

## From since last run
- [#channel] [Owner] Action — due <date>
- ...
```

---

## Analysis parameters

### Time windows

Each run computes two non-overlapping UTC windows:

**Window A — previous business day:** `[PREV_DATE 00:00:00 UTC, PREV_DATE 23:59:59 UTC]`

| Today (local DOW) | Looks back at |
|---|---|
| Mon | Fri |
| Tue–Fri | previous calendar day |
| Sat | Fri |
| Sun | Fri |

**Window B — since last run:** `[max(LAST_RUN, PREV_DATE 23:59:59 UTC + 1), SCRIPT_START_TS]`

- `LAST_RUN` comes from `~/slack-summary/.last-run` (UTC Unix seconds, written by the previous successful run).
- The `max` ensures Window B never overlaps with Window A — same messages are never summarized twice.
- **First run** (no state file): `LAST_RUN` defaults to `PREV_DATE 23:59:59 UTC + 1`, so Window B becomes "from end of yesterday to now" (typically "today so far").
- Window B is degenerate (empty) when `SCRIPT_START_TS == SINCE_AFTER_TS`. The report renders the heading with `_No new messages since last run._`

Both windows are computed in `run.sh` and passed to the prompt as `{{AFTER_TS}}` / `{{END_TS}}` (Window A) and `{{SINCE_AFTER_TS}}` / `{{SINCE_BEFORE_TS}}` / `{{SINCE_FROM_HUMAN}}` / `{{SINCE_TO_HUMAN}}` (Window B).

The single slackdump export covers `[PREV_DATE 00:00:00 UTC, SCRIPT_START_TS]` — wider than either window individually — and the prompt instructs Claude to filter messages by `ts` per section.

### What gets extracted per channel, per window

The prompt instructs Claude to run the same per-channel analysis for **both** Window A and Window B, then aggregate at the end:

1. **Sub-thread breakdown** — split the channel's activity in this window into discrete topics (each parent message + replies = one sub-thread; substantial standalone messages count too; trivial standalone messages get aggregated into one `Other` group).
2. For each sub-thread, capture:
   - **Initiator** — who started it
   - **Most active** — 2–4 names who drove the discussion
   - **Discussion** — key points, decisions, updates, with specifics (numbers, host/system names, dates)
3. **Action items** — each prefixed with the channel name, plus owner (resolved to display name when possible) and follow-up date if stated
4. **References** — Jira tickets, doc URLs, GitHub PRs, FastTrack/ECX tickets, runbooks, with one-line context each
5. **Name resolution** — `list_users` is called once (after `load_source`) to map Slack user IDs to display names throughout both sections
6. **Channels with no activity in this window** — listed under `Quiet channels` at the end of the window section
7. **Consolidated list at the very bottom** — every action item from both windows re-listed, grouped by window (`## From previous business day` / `## From since last run`), for one scannable view

Threads are assigned to the window containing the **parent message's** ts, even if late replies land in the other window.

### Slackdump export options

`run.sh` calls `slackdump export` once per run, with a window wide enough to cover both Window A and Window B:

- `-time-from "${PREV_DATE}T00:00:00"` — start of previous business day in UTC
- `-time-to "$DUMP_TIME_TO"` — `SCRIPT_START_TS` formatted as `YYYY-MM-DDTHH:MM:SS` UTC
- `-files=false` — skip file attachment downloads (much faster, smaller zips)
- `-channel-users` — bundle only users referenced in the dumped channels (smaller `users.json`)
- `-y` — non-interactive

The output is a Slack-export-format zip containing `users.json`, `channels.json`, and per-channel JSON files. The MCP server's `load_source` opens this directly. The prompt then filters messages by ts per window.

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
.last-run ─────┤
               ▼
       run.sh computes both UTC windows (biz day + since last run)
               │
               ▼
   slackdump export ──► dumps/<TODAY>.zip  (covers both windows)
               │
               ▼
   ensure_mcp_server (auto-launch if needed)
               │
               ▼  HTTP on 127.0.0.1:8483
   claude -p ─── load_source(dumps/<TODAY>.zip)
               ├─ list_users
               ├─ get_messages (per channel — partition by ts)
               └─ get_thread (per parent message)
               │
               ▼
   markdown stdout ──► summaries/<TODAY>.md
               │
               ▼
   cmark-gfm + HTML wrapper ──► summaries/<TODAY>.html
               │
               ▼
   atomic write: SCRIPT_START_TS ──► .last-run
```

The MCP server is started without an archive argument — Claude calls `load_source` to point it at each run's fresh zip, so the server can be long-lived across runs and across other Slackdump uses. The `.last-run` write happens last, so a failed run won't advance the window marker.

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

### "Since last run" section is empty

Expected if you re-ran the script recently (the window between last run and now is just minutes). The report renders the heading then `_No new messages since last run._` and continues with the consolidated action items list.

### Force a wider "since" window

To re-summarize a specific past period in the second section, manually overwrite `.last-run` with the desired start timestamp (UTC Unix seconds) before running:

```bash
# e.g. force the since-window to start 4 hours ago
echo "$(($(date -u +%s) - 14400))" > ~/slack-summary/.last-run
~/slack-summary/run.sh
```

---

## File reference

| Path | Purpose |
|---|---|
| `run.sh` | Main entry point |
| `install.sh` | One-time installer (idempotent) |
| `prompt.md` | Summarization prompt template (two-window) |
| `channels.txt.example` | Template — copied to `channels.txt` on first install |
| `channels.txt` | Per-user channel list (gitignored) |
| `dumps/<TODAY>.zip` | Slackdump export covering both windows (gitignored) |
| `summaries/<TODAY>.md` | Markdown report (gitignored) |
| `summaries/<TODAY>.html` | Styled HTML report (gitignored) |
| `.last-run` | UTC Unix timestamp of last successful run (gitignored, per-user state) |
| `mcp-server.log` | Log file from any auto-launched MCP server (gitignored) |
| `.gitignore` | Excludes generated/personal files |
| `LICENSE` | MIT license |
| `~/Library/Caches/slackdump/<workspace>.bin` | Cached Slackdump auth credentials |
| `~/.claude.json` | Claude Code config — must contain the `local-mcp` HTTP entry (added by `install.sh`) |

---

## License

[MIT](LICENSE) — see the `LICENSE` file.
