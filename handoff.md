# Handoff

## 1. Snapshot

- Generated at: 2026-05-12T22:37:00Z (UTC) / 2026-05-12 15:37 PT
- Repository path: `/Users/justin.lau/slack-summary`
- Git branch: `main`
- HEAD commit: `afb103122cf3b3850f6585d46329462bc7fa62b5` (`afb1031` — "Document the update flow")
- Working tree status: **clean**. `git status` reports "nothing to commit, working tree clean". Local `main` is up to date with `origin/main`.
- Primary task / objective: build and harden a local Slack daily-summary pipeline (`slackdump` → Claude Code → HTML), distribute it to a team via a private GitHub repo, and add a second report section covering "everything since the script last ran". All shipped in this session.
- Current status: feature-complete and shipped. No outstanding work items from the session.
- Confidence level: **High** — pipeline was verified end-to-end (dry-run and real run with 8 channels producing the expected two-section output), state-file write was confirmed, and every commit was pushed to `origin/main`.

## 2. Session Summary

### User goal
Take a single-channel slackdump-MCP experiment from earlier and turn it into a reusable, team-distributable daily-summary tool that:
1. Pulls the previous business day's messages from a list of Slack channels.
2. Summarizes them through Claude Code with rich per-channel sub-thread breakdowns, named action items, and reference links.
3. Renders to a styled HTML page.
4. Also reports "since last run" in a second section.
5. Is easy for a teammate to install fresh.

### Important constraints (from user)
- macOS-only is acceptable.
- Trigger is manual (no cron/launchd).
- Output should be HTML (markdown kept as a side artifact).
- `channels.txt` should accept full Slack URLs and bare IDs.
- `cmark-gfm` should auto-install on first run if missing.
- For the two-section change: dedupe windows (since-section starts at end of previous business day so messages aren't summarized twice).
- For the two-section change: name output by today's local date, not the previous business day.
- Never modify global `git config` without explicit permission. (User commits use `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars.)
- The user prefers MIT license over GPL-3.0 for this internal tooling.

### Major decisions made
- Use `slackdump export` (not `dump` or `archive`) — `export` is the only sub-command that bundles `users.json` for name resolution and produces a zip directly via `-o foo.zip`.
- Persist last-run state in `~/slack-summary/.last-run` (single UTC Unix timestamp). Captured at script **start**, written at script **end** (atomic `mv` of a `.tmp`). Failed runs do not advance the marker.
- Single combined slackdump call covering both windows; the prompt instructs Claude to partition by `ts` per section. (Cheaper than two slackdump invocations.)
- Output filenames switched from `<PREV_DATE>.md/.html` to `<TODAY>.md/.html` once the report started covering both windows.
- The Slackdump MCP server is registered with Claude Code at **user scope** via `claude mcp add --scope user ...` (set by `install.sh`). User's existing project-scoped `local-mcp` entry under `~/.claude.json -> projects./Users/justin.lau` was left in place (it's redundant but not harmful).
- README's Quick Start section now contains the full clone → install → auth → populate → run flow (formerly buried in "Sharing with teammates").
- Distribution channel: private GitHub repo at https://github.com/justinhlau/pmo-slack-summary.
- License: MIT, copyright "Justin Lau".

### What was completed (all merged + pushed)
- `run.sh`: location-aware, computes both UTC windows, persists `.last-run`, widens the slackdump call to span both windows, auto-installs `cmark-gfm`, auto-launches the MCP server, supports `--dry-run`, accepts env overrides (`CLAUDE_BIN`, `SLACKDUMP_BIN`, `CMARK_BIN`).
- `prompt.md`: two-window structure with per-section sub-thread breakdowns, channel-tagged action items, references with clickable markdown links, quiet channels, and a final consolidated action items section grouped by window.
- `install.sh`: idempotent installer for `slackdump`, `cmark-gfm`, and Claude Code CLI; registers the MCP server; seeds `channels.txt` from `channels.txt.example`.
- `channels.txt` parser accepts bare IDs **and** full Slack URLs (`https://workspace.slack.com/archives/CXXX[/p...][?...]`) plus inline `#` comments.
- `.gitignore` excludes `dumps/`, `summaries/`, `mcp-server.log`, `.last-run`, `channels.txt`, `.DS_Store`.
- `README.md`: rewritten with the comprehensive flow in Quick Start, plus an "Updating an existing install" subsection.
- `LICENSE`: swapped from auto-generated GPL-3.0 to MIT.
- Git repo initialized in `~/slack-summary/`, pushed to https://github.com/justinhlau/pmo-slack-summary, branch `main`.

### What remains incomplete
- Nothing the user asked for. The two-section feature shipped and was verified end-to-end on 2026-05-11.

### What is blocked
- Nothing.

## 3. Project Context

### App/product purpose
A local CLI tool that produces a daily Slack-channel summary in HTML. Aimed at a PMO use case — read what happened yesterday across project channels, plus anything new since the last time the user ran the script.

### Tech stack
- macOS host (BSD `date` flags, `~/Library/Application Support` paths — Linux/WSL would require changes).
- `bash` (`run.sh`, `install.sh`).
- `slackdump` v3.x (Homebrew). Sub-commands used: `slackdump export`, `slackdump mcp`, `slackdump workspace`.
- Claude Code CLI v2.x (native macOS install via `curl https://claude.ai/install.sh | bash`).
- `cmark-gfm` 0.29.x (Homebrew) — markdown → HTML.
- Slackdump's bundled MCP HTTP server at `http://127.0.0.1:8483/mcp`. Tools exposed: `load_source`, `list_channels`, `list_users`, `get_channel`, `get_messages`, `get_thread`, `get_workspace_info`, `command_help`.

### Package manager / build system
None — pure shell. Homebrew installs the binaries; no `package.json`, no `Makefile`.

### Important directories (gitignored unless noted)
- `dumps/` — Slackdump export zips, one per run, named `<TODAY>.zip`.
- `summaries/` — generated `<TODAY>.md` and `<TODAY>.html`.
- (No `src/`, `tests/`, or similar — all logic lives in two files: `run.sh` and `prompt.md`.)

### Important entry points
- `~/slack-summary/run.sh` — main pipeline. Run with no args for normal mode, `--dry-run` for preview.
- `~/slack-summary/install.sh` — one-time installer, idempotent.

### Important config files
- `~/slack-summary/channels.txt` (per-user, gitignored) — channel IDs or Slack URLs.
- `~/slack-summary/prompt.md` (in repo) — summarization prompt template with `{{...}}` placeholders.
- `~/slack-summary/.last-run` (per-user, gitignored) — UTC Unix timestamp of last successful run.
- `~/.claude.json` (system; not in repo) — Claude Code config. Contains the `local-mcp` HTTP server entry both at user scope (added by `install.sh`) and at project scope under `/Users/justin.lau` (legacy, harmless).
- `~/Library/Caches/slackdump/<workspace>.bin` — Slackdump auth cache (binary, encrypted).

### Relevant docs / instructions found in repo
- `README.md` — full user-facing docs (385 lines). Sections: Quick start, Prerequisites, Configuration, Usage, Output, Analysis parameters, Architecture, Troubleshooting, File reference, License.
- `LICENSE` — MIT, 21 lines.
- `channels.txt.example` — annotated template for `channels.txt`.

### Coding conventions / patterns
- `run.sh` uses `set -euo pipefail`, computes its own `DIR` via `BASH_SOURCE` (so it's portable), and uses BSD `date -v-Nd` for date math.
- Binary resolution pattern: try `command -v X`, then a fallback list of known install paths (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`).
- Atomic state writes: `printf '...' > foo.tmp && mv foo.tmp foo`.
- Prompt templating: `${PROMPT//\{\{PLACEHOLDER\}\}/$VALUE}` bash substitution.
- Markdown output: prompt is told **not** to wrap the response in a code fence, to render URLs as `[label](url)` (not backticks), and to use `<channel>` and `<owner>` prefixes on action items.
- Commits in this session were authored as `Justin Lau <justin.lau@lambdal.com>` via env vars (user has no global git identity set; this was confirmed and authorized).
- Commit message style: short imperative subject (under ~50 chars), blank line, prose body explaining the why, then `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` trailer.

## 4. Current Git State

- Current branch: `main`
- HEAD commit: `afb103122cf3b3850f6585d46329462bc7fa62b5`
- Remote: `origin https://github.com/justinhlau/pmo-slack-summary.git` (fetch and push)
- Working tree status (`git status --short`): empty (clean)
- Recent commits (newest first):
  - `afb1031` Document the update flow
  - `2fdd9c7` Move full setup flow into Quick start
  - `938046e` Add since-last-run section to daily report
  - `c6004b7` Update README with repo URL and license
  - `3c19e7b` Swap LICENSE from GPL-3.0 to MIT
  - `9a63209` Slack daily summarizer pipeline
  - `e6a9039` Initial commit (auto-generated by GitHub repo creation)

### Changed/staged/unstaged/untracked
- Changed: none.
- Staged: none.
- Unstaged: none.
- Untracked (working tree, all gitignored): `dumps/`, `summaries/`, `.last-run`, `mcp-server.log`, `channels.txt`, `.DS_Store`.
- Deleted: none.
- Renamed: none.

### Local-only files present on disk (gitignored, per-user state)
- `channels.txt` — 8 channel IDs configured (one for each project channel the user wants summarized; not enumerated here for privacy).
- `dumps/2026-05-07.zip`, `dumps/2026-05-08.zip`, `dumps/2026-05-11.zip`, `dumps/2026-05-12.zip`.
- `summaries/2026-05-07.md`, `summaries/2026-05-08.{md,html}`, `summaries/2026-05-11.{md,html}`, `summaries/2026-05-12.{md,html}`.
- `.last-run` — 11-byte file containing one UTC Unix timestamp from 2026-05-12 15:33 local. (A run happened on 2026-05-12 — Unknown whether by the user manually or by some other trigger; not part of this session's automated work.)
- `mcp-server.log` — log from the slackdump MCP server when it was auto-launched.

## 5. Files Changed This Session

All listed files are tracked in the repo and were committed/pushed during this session. None are currently unstaged or untracked.

### `run.sh`

- Status: modified across multiple commits (currently committed and clean)
- Purpose of change: turn a single-day biz-day summarizer into a two-window pipeline (biz day + since last run) with state persistence, plus harden it for team distribution.
- Key implementation details:
  - `SCRIPT_START_TS=$(date -u +%s)` captured at top; same value persisted to `.last-run` at the end on success.
  - Two windows: `[AFTER_TS, END_TS]` for biz day, `[max(LAST_RUN, END_TS+1), SCRIPT_START_TS]` for since-last-run.
  - Single `slackdump export` call from `${PREV_DATE}T00:00:00` to `$DUMP_TIME_TO` (now, UTC).
  - `DUMP_ZIP`, `OUT`, `HTML_OUT` use `$TODAY` (local date), not `$PREV_DATE`.
  - Binary resolution for `claude` skips the desktop-app-bundled Linux ELF at `~/Library/Application Support/Claude/claude-code-vm/...`.
  - MCP server auto-launch via `ensure_mcp_server` (checks `/dev/tcp/127.0.0.1/8483`; if closed, `nohup slackdump mcp -transport http -listen ...` and waits up to 10s).
  - `--dry-run` prints both windows + state file value + dump window + output paths.
  - Atomic state file write: `printf '%s\n' "$SCRIPT_START_TS" > "$LAST_RUN_FILE.tmp" && mv "$LAST_RUN_FILE.tmp" "$LAST_RUN_FILE"`.
- Important functions/commands affected: `slackdump export`, `claude --print --allowedTools mcp__local-mcp__{load_source,list_channels,list_users,get_messages,get_thread,get_channel}`, `cmark-gfm --extension autolink --extension strikethrough --extension table`.
- Known risks: macOS-only date math (BSD `date -v` flags); will not run on Linux without porting.
- Follow-up needed: none currently.

### `prompt.md`

- Status: modified, committed.
- Purpose of change: instruct Claude to produce two top-level sections (biz day, since last run), filter messages by `ts` per section, and consolidate action items at the bottom grouped by window.
- Key implementation details:
  - Calls `load_source({{DUMP_ZIP}})` first (fatal if it errors).
  - Calls `list_users` once for name resolution.
  - Per-section structure: per-channel sub-thread breakdown with `Initiator` / `Most active` / `Discussion`, `**Action items**` block (channel-name-prefixed bullets with owner + due date), `**References**` block (markdown links + Jira IDs).
  - Quiet channels listed at the end of each window.
  - Final `# Consolidated action items` with `## From previous business day` / `## From since last run` subheadings.
  - Empty-Window-B fallback: render heading + `_No new messages since last run._`.
  - Explicit "do not wrap in a code fence" and "use [label](url) syntax for URLs" instructions.
- Risks: model occasionally violates the no-code-fence rule. Re-running usually fixes.

### `install.sh`

- Status: modified (created mid-session), committed.
- Purpose: idempotent installer for teammates.
- Key details:
  - Refuses to run on non-Darwin.
  - Requires Homebrew (prints install instructions if missing).
  - `brew install slackdump cmark-gfm` (skips if present).
  - `curl -fsSL https://claude.ai/install.sh | bash` (skips if Claude binary already present).
  - `claude mcp add --scope user --transport http local-mcp http://127.0.0.1:8483/mcp` (skips if `claude mcp list` already shows `local-mcp:`).
  - Creates `dumps/`, `summaries/`.
  - Seeds `channels.txt` from `channels.txt.example` if missing.
  - Prints next-step instructions (slackdump workspace new + claude auth + edit channels.txt + run).
- Risks: assumes Apple Silicon / Intel Homebrew prefix layouts.

### `channels.txt.example`

- Status: created mid-session, committed.
- Purpose: template seeded into `channels.txt` by `install.sh` on first install.
- Notes: shows both bare-ID and full-URL formats; explains inline `#` comments are stripped.

### `.gitignore`

- Status: modified, committed.
- Purpose: exclude per-user state and generated artifacts.
- Entries: `dumps/`, `summaries/`, `mcp-server.log`, `.last-run`, `channels.txt`, `.DS_Store`.

### `README.md`

- Status: modified, committed.
- Purpose: user-facing docs reorganized so the canonical setup flow is in Quick start (first scrollable section after the intro), with troubleshooting and an "Updating an existing install" subsection.
- Notable sections: Quick start (now comprehensive), Prerequisites (slimmed), Configuration, Usage, Output, Analysis parameters (with both window definitions), Architecture (ASCII diagram), Troubleshooting (including "Force a wider since-window"), File reference, License.

### `LICENSE`

- Status: replaced (GPL-3.0 → MIT), committed.
- Purpose: less-restrictive license for internal tooling.

## 6. Implementation Details

### New logic added
- `.last-run` state file (per-user UTC timestamp, atomically updated on success).
- "Since last run" window computation with dedup against the biz-day window.
- First-run fallback to `END_TS + 1` when `.last-run` is absent or non-numeric.
- Channel ID parser that strips full Slack URLs down to `CXXXXXXX` and removes inline `#` comments.
- `cmark-gfm` auto-install path inside `run.sh` (Homebrew, errors clearly if `brew` is missing).
- HTML wrapper around the cmark output (inline `<style>` block).
- `install.sh` (didn't exist at session start).

### Existing logic modified
- Slackdump invocation: changed from `slackdump dump -time-to ${PREV_DATE}T23:59:59` (single day, no users) to `slackdump export -channel-users -time-to $DUMP_TIME_TO` (wider window, bundles `users.json`).
- Output filenames switched from `<PREV_DATE>` to `<TODAY>`.
- Title in HTML wrapper updated to use `$TODAY`.

### APIs affected
- The slackdump MCP server's tool surface — `load_source` is now called by the prompt to swap the active archive on each run.

### Functions / commands / endpoints affected
- `run.sh` (shell function `mcp_port_open` and `ensure_mcp_server` preserved; new state-file write block added at end).
- Claude CLI invocation: `--allowedTools` expanded to include `list_users` and `get_channel` (added when name-resolution and quiet-channel logic landed).

### Database / data model / schema
- None. No database. State is a single text file.

### Migrations
- None.

### Config changes
- `~/.claude.json` user-scope `mcpServers.local-mcp` entry added via `claude mcp add --scope user ...` (done implicitly during the verification run of `install.sh`).
- Pre-existing project-scope entry at `projects./Users/justin.lau.mcpServers.local-mcp` was **not removed**; both point at the same URL.

### Dependency changes
- Added `cmark-gfm` (Homebrew) as an explicit runtime dependency. Auto-installs on first `run.sh` invocation if missing.
- `gh` (GitHub CLI) was installed via Homebrew during the session to assist with the GitHub push (not used by `run.sh` itself, not a runtime dep).

### UI/UX changes
- Each report now has two `<h1>` sections (was one) plus a `<h1> Consolidated action items` block.
- HTML auto-links bare URLs via `cmark-gfm --extension autolink` (though prompt is told to use `[label](url)` form, which renders even nicer).

### Error handling changes
- `run.sh` exits with clear messages if `slackdump`, `claude`, `cmark-gfm` are missing.
- MCP server start failure (>10s wait) exits with `Error: MCP server didn't come up within 10s. See $MCP_LOG`.
- Empty `channels.txt` errors out before doing any work (except in dry-run mode).
- Atomic state write means a partial run never advances the marker.

### Performance considerations
- Single combined slackdump call instead of two — saved ~10–20s per run.
- `slackdump -files=false` avoids attachment downloads.
- `slackdump -channel-users` keeps `users.json` small.

### Security / privacy considerations
- No secrets written to the repo. Authentication caches (`~/.claude/`, `~/Library/Caches/slackdump/`) live entirely outside the working tree.
- `channels.txt` is gitignored, so teammates' channel lists never get pushed.
- `dumps/` and `summaries/` are gitignored — contain Slack message content that should not leave each user's machine.
- The MCP server listens on `127.0.0.1:8483` (loopback only).

### Backward compatibility considerations
- Old output filenames `<PREV_DATE>.md/.html` will no longer be created; new runs produce `<TODAY>.md/.html`. Existing dated files in `summaries/` are left untouched.
- `.last-run` first-run fallback ensures pre-existing installs (which didn't have the file) work seamlessly.

## 7. Commands Run

Many commands were run during the session. Highlights only — full transcript was preserved in the chat history but is not reproduced here.

```sh
brew install slackdump
```
Result: not run by Claude — installed prior to this session (verified via `command -v slackdump` returning `/opt/homebrew/bin/slackdump`).

```sh
curl -fsSL https://claude.ai/install.sh | bash
```
Result: **passed**. Installed Claude Code CLI v2.1.137 at `~/.local/bin/claude`. Note: `~/.local/bin` is not on the user's PATH per the installer's warning — `run.sh` resolves the absolute path directly so this doesn't matter for the daily workflow.

```sh
brew install cmark-gfm
```
Result: **passed**. Installed v0.29.0.gfm.13 at `/opt/homebrew/Cellar/cmark-gfm/0.29.0.gfm.13`, symlinked at `/opt/homebrew/bin/cmark-gfm`.

```sh
brew install gh
```
Result: **passed**. Installed GitHub CLI v2.92.0. Used once to verify auth status (`gh auth status`) and confirmed already logged in as `justinhlau`. Not used after that; the actual push used plain `git push`.

```sh
~/slack-summary/run.sh --dry-run
```
Result: **passed**. Confirmed both window timestamps, today-based filenames, and full prompt rendering with all placeholders substituted.

```sh
~/slack-summary/run.sh
```
Result: **passed**. End-to-end run on 2026-05-11 produced:
- `dumps/2026-05-11.zip` (85 KB, 8 channels across both windows).
- `summaries/2026-05-11.md` (about 24 KB; 119–141 lines depending on exact run).
- `summaries/2026-05-11.html` (about 29 KB, three `<h1>` sections as expected).
- `.last-run` written atomically.
Slackdump phase: ~22 s. Claude phase: ~17 s. Total wall time ~40 s.

```sh
~/slack-summary/install.sh
```
Result: **passed**. Idempotent on a fully-configured machine; on first run, registered `local-mcp` MCP server at user scope.

```sh
cd ~/slack-summary && git init -b main
cd ~/slack-summary && git add .gitignore README.md channels.txt.example install.sh prompt.md run.sh
GIT_AUTHOR_NAME="Justin Lau" GIT_AUTHOR_EMAIL="justin.lau@lambdal.com" GIT_COMMITTER_NAME="..." GIT_COMMITTER_EMAIL="..." git commit -m "..."
cd ~/slack-summary && git remote add origin https://github.com/justinhlau/pmo-slack-summary.git
cd ~/slack-summary && git pull --rebase -X theirs origin main
cd ~/slack-summary && git push -u origin main
```
Result: **passed**. Rebase was needed because the GitHub repo had an auto-generated initial commit (`LICENSE` + 1-line README); the rebase kept LICENSE (later replaced) and our README. All subsequent commits were pushed with `git push` (no force).

```sh
curl -sS -X POST http://127.0.0.1:8483/mcp -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d '{"jsonrpc":"2.0","method":"initialize",...}'
```
Result: **passed**. Used during the option-2 investigation to enumerate the slackdump MCP server's tool list and confirm there's no built-in re-dump tool. Session expired naturally after use.

```sh
bash -n ~/slack-summary/run.sh
```
Result: **passed**. Syntax check after each major edit.

## 8. Validation Status

- Tests run: **No automated tests exist**. This is a pure shell + prompt project; manual verification only.
- Tests passing: N/A.
- Tests failing: N/A.
- Build status: N/A (no build).
- Typecheck status: N/A.
- Lint status: N/A (`bash -n` was used as a syntax check; passed on the final `run.sh`).
- Formatting status: N/A.
- Manual verification:
  - Dry-run on 2026-05-11: passed (both windows resolved correctly with first-run fallback).
  - Real run on 2026-05-11: passed (8 channels dumped, both H1 sections rendered, `.last-run` advanced).
  - HTML opened in default browser (via macOS `open`): passed (3 `<h1>` tags, 8+ `<a href>` links, valid structure).
  - Installer idempotency check: re-ran `install.sh` after first run; correctly skipped already-installed binaries and detected existing `local-mcp` registration.
  - MCP server auto-launch path: verified by killing the running server and re-running `run.sh`; the script launched a new one and proceeded.
- Untested areas:
  - Behavior when Slackdump auth has expired during a headless run — assumed to surface as a `slackdump export` non-zero exit, which `set -e` will catch.
  - Behavior with 0-channel `channels.txt` — handled with an early exit message; not exercised end-to-end this session.
  - Behavior on a clean fresh machine (full `install.sh` from zero). The installer was run on the developer's already-configured machine, so it always took the "already installed" paths.
- Known regressions: none observed.
- Confidence in current state: **High** for the user's machine; **Medium-High** for a fresh teammate's machine (installer path was exercised but every dependency was already present).

## 9. Known Issues and Blockers

- The project-scoped `local-mcp` entry under `~/.claude.json -> projects./Users/justin.lau.mcpServers.local-mcp` is redundant with the user-scope entry added by `install.sh`. Both point at the same URL so behavior is unchanged, but a tidy-up could remove the project-scope one via `claude mcp remove --scope local local-mcp` after `cd ~`.
- Headless `claude -p` invocation occasionally hallucinates its tool list and refuses to call MCP tools (observed once during the verbose-prompt rollout; a retry succeeded). The prompt now reliably triggers the right tool calls.
- Slackdump's progress output (`. o O @ * .` spinner) is verbose on stderr. Currently unfiltered; could be quieted via `-log` to a file.
- `cmark-gfm` is invoked with the `table` extension even though current prompt output rarely uses tables. Harmless; left enabled for forward compatibility.
- The desktop Claude app's bundled binary at `~/Library/Application Support/Claude/claude-code-vm/<version>/claude` is a Linux ELF and cannot be run directly on macOS. `run.sh` now skips it and uses `~/.local/bin/claude` first. Future Claude desktop updates that bump the SDK version will not break this.

## 10. Environment and Configuration

- Required runtime versions:
  - macOS (Apple Silicon verified; Intel assumed compatible via the Homebrew prefix fallbacks in `run.sh`).
  - Homebrew (any recent version).
  - `slackdump` v3.x.
  - Claude Code CLI v2.x.
  - `cmark-gfm` v0.29.x.
- Package manager: Homebrew.
- Required services:
  - The Slackdump MCP HTTP server on `127.0.0.1:8483` — `run.sh` auto-launches if not running.
- Required environment variable names (none are secret; all optional):
  - `CLAUDE_BIN` — override path to the Claude Code CLI.
  - `SLACKDUMP_BIN` — override path to slackdump.
  - `CMARK_BIN` — override path to cmark-gfm.
- Local setup assumptions:
  - Homebrew installed at `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel).
  - Slackdump workspace pre-authenticated (one-time `slackdump workspace new <slug>` browser flow).
  - Claude Code CLI pre-authenticated (one-time `claude` interactive launch).
- Database / migration state: N/A.
- Feature flags: N/A.
- External integrations:
  - Slack (via slackdump's browser-auth Slack scraping).
  - Anthropic Claude API (via Claude Code CLI's auth).
  - GitHub (for distribution, push from local clone to https://github.com/justinhlau/pmo-slack-summary).
- Ports / local URLs: `http://127.0.0.1:8483/mcp` for the slackdump MCP server.
- OS assumptions: macOS only (BSD `date`, `~/Library/...` paths).

(No secret values are included in this handoff. Auth caches live in `~/.claude/` and `~/Library/Caches/slackdump/<workspace>.bin` and are never read or printed by `run.sh`, `install.sh`, or `prompt.md`.)

## 11. Important Parameters for Session Continuity

- Current objective: project is feature-complete and shipped. No active task in flight.
- Current completion state: 100% of the user's explicit asks during this session are done and pushed.
- Exact files changed (tracked in repo): `.gitignore`, `LICENSE`, `README.md`, `channels.txt.example`, `install.sh`, `prompt.md`, `run.sh`.
- Exact files that should be reviewed first if resuming work:
  - `~/slack-summary/run.sh` — orchestration.
  - `~/slack-summary/prompt.md` — Claude instructions.
  - `~/slack-summary/README.md` — user-facing docs (also the GitHub landing page).
- Exact commands to run first when resuming:
  - `cd ~/slack-summary && git status && git log -n 5 --oneline` to confirm state.
  - `~/slack-summary/run.sh --dry-run` to sanity-check the pipeline without consuming Claude credits.
- Exact commands that already passed (most recent):
  - `~/slack-summary/run.sh` (end-to-end, 2026-05-11).
  - `~/slack-summary/install.sh` (idempotent re-run, 2026-05-11).
  - `git push origin main` for commits `9a63209`, `3c19e7b`, `c6004b7`, `938046e`, `2fdd9c7`, `afb1031`.
- Exact commands that failed: none currently (some failed and were fixed during the session — see commit history for the fix sequence: `dump` → `export`, sqlite vs zip, `claude-code-vm` Linux ELF discovery, etc.).
- Tests / build / lint / typecheck status: no automated checks exist; `bash -n run.sh` passed.
- Known broken behavior: none.
- Known good behavior: the full pipeline produces a two-section HTML report with name resolution, clickable links, and a consolidated action items list.
- User preferences:
  - Concise, factual responses; flag risks; ask before destructive actions.
  - Prefer minimal change over architectural overhauls.
  - Never modify global `git config` without explicit permission.
  - MIT over GPL for internal tooling.
- User constraints:
  - macOS host.
  - Manual trigger (no scheduler).
  - HTML output.
  - Dedupe overlapping windows.
  - Output named by today's date.
- Architectural constraints:
  - Pure shell pipeline; no compiled code; no language runtimes beyond what slackdump/claude/cmark-gfm bring.
  - Single combined slackdump dump per run.
  - State stored in a single text file.
- Compatibility requirements:
  - macOS only; Linux/WSL would need separate code paths for BSD `date`.
- Style conventions:
  - Bash with `set -euo pipefail`, BSD-compatible flags.
  - Atomic file writes via tmpfile + `mv`.
  - Imperative commit subjects under ~50 chars, body explaining the why, `Co-Authored-By` trailer.
- Performance constraints: end-to-end should remain under ~60 s for ~8 channels.
- Security / privacy constraints: never commit `dumps/`, `summaries/`, `channels.txt`, `.last-run`, `mcp-server.log` (already enforced by `.gitignore`).
- Files or behavior that must not be changed without user input:
  - User's `~/.claude.json` MCP-server entries beyond what `install.sh` adds.
  - User's global git config (still unset, intentionally).
- Open design decisions: none currently open.
- External dependencies / services: Slack (slackdump), Anthropic (Claude Code CLI), GitHub (distribution).
- Required environment variable names: `CLAUDE_BIN`, `SLACKDUMP_BIN`, `CMARK_BIN` (all optional overrides; values are absolute paths to binaries, not secrets).
- Assumptions made during the session:
  - The "previous business day" is computed in the user's local timezone (not UTC) for the day-of-week check, then materialized as UTC 00:00–23:59 for the timestamp window. This is intentional and matches user expectation but could be revisited.
  - First-run since-window defaults to "end of yesterday → now" rather than empty; user explicitly accepted dedupe-via-`max` for the steady-state case but didn't separately confirm the first-run behavior.

## 12. Next Recommended Actions

Project is at a clean stopping point. The next session is more likely to be a small enhancement, a bug report, or a workflow change than continued in-flight work. Suggested order:

1. Read `handoff.md` (this file).
2. Inspect the current git state:
   ```sh
   cd ~/slack-summary
   git status --short
   git branch --show-current
   git rev-parse HEAD
   git log -n 5 --oneline
   ```
3. Review these files if making changes:
   - `~/slack-summary/run.sh`
   - `~/slack-summary/prompt.md`
   - `~/slack-summary/README.md`
4. Run these commands to confirm the pipeline still works (does not write to GitHub):
   ```sh
   ~/slack-summary/run.sh --dry-run
   ```
   If a full run is appropriate (consumes Claude credits and produces a new `.last-run` advancement, dump, and report):
   ```sh
   ~/slack-summary/run.sh
   ```
5. Continue with whatever the user asks. There is no in-flight task to resume.
6. Validate by opening `~/slack-summary/summaries/<TODAY>.html` and confirming two `<h1>` sections plus a final consolidated section.
7. Avoid:
   - Modifying `~/.claude.json` beyond what `install.sh` does.
   - Setting global git config without explicit permission.
   - Reintroducing the desktop `claude-code-vm` path into `run.sh`'s binary resolution (it's a Linux ELF on macOS).
   - Using `slackdump dump` or `slackdump archive` instead of `slackdump export` (only `export` bundles `users.json` and produces a zip-format archive that the MCP server's `load_source` understands as the historic "dump"-type format).

## 13. Open Questions

- Question: Should `install.sh` also remove the legacy project-scope `local-mcp` entry under `~/.claude.json -> projects.<user-home>.mcpServers`, or leave it alone?
  - Why it matters: cleanliness; both entries point at the same URL so behavior is unchanged either way.
  - Suggested default: leave alone (current behavior). Removing it requires `claude mcp remove --scope local local-mcp` from within the user's home as the cwd, which is a minor footgun.

- Question: Is the first-run since-window default ("end of yesterday → now") the right choice, or should the first run produce only the biz-day section and skip the since-section?
  - Why it matters: a brand-new install's first since-section will retroactively cover ~12 hours of "today so far," which could be surprising.
  - Suggested default: keep the current behavior (more useful summary than a blank section).

- Question: The user's `.last-run` file already contains a timestamp from 2026-05-12 15:33 local, suggesting at least one run happened on 2026-05-12 outside of Claude's verified runs (probably manually by the user). Should anything in `handoff.md` change in response?
  - Why it matters: confirms the user is using the tool; doesn't change the codebase. Just noting the artifact.
  - Suggested default: no action.

## 14. Important Constraints / Do-Not-Forget Notes

- User preferences:
  - Prefers concise, accurate responses with risks called out.
  - Wants security/destructive actions flagged before execution.
  - Likes commit messages that explain the *why*, not just the *what*.
- Architectural constraints:
  - Pure shell; no compiled tooling beyond Homebrew packages.
  - macOS only; no Linux/WSL port without explicit code paths.
  - Single combined `slackdump export` per run (do not split into two dumps).
- Compatibility requirements:
  - First-run fallback for `.last-run` must remain so existing installs upgrade seamlessly.
  - Output filename convention (`<TODAY>.{md,html}`) was a deliberate choice — do not revert to `<PREV_DATE>` without re-asking.
- Style conventions:
  - Bash with `set -euo pipefail`, atomic state writes via tmp+`mv`.
  - Commit subject under ~50 chars; body explains *why*; `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` trailer on all commits authored with Claude's help.
  - All commits in this repo use `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars (`Justin Lau <justin.lau@lambdal.com>`); user has no global git identity set and asked it not be changed.
- Performance constraints: keep wall time under ~60 s for ~8 channels.
- Security / privacy constraints:
  - Never commit `channels.txt`, `dumps/`, `summaries/`, `.last-run`, `mcp-server.log`.
  - Never reproduce Slack message content, channel IDs, or user IDs in committed files.
  - Never modify `~/.claude.json` beyond what `install.sh` does.
- Testing requirements: none formal; manual verification via `--dry-run` and one real run is the standard.
- Files or behavior that must not be changed without user input:
  - `~/.claude.json` mcp config (beyond what install.sh sets).
  - Global git config.
  - `LICENSE` file (it's MIT now; user explicitly chose this).
- Prior failed approaches to avoid:
  - `slackdump dump` (no users.json, breaks name resolution).
  - `slackdump archive` (produces a SQLite directory, not a zip; MCP `load_source` expects the zip-form export).
  - Using the desktop-app-bundled `~/Library/Application Support/Claude/claude-code-vm/<version>/claude` binary (Linux ELF, won't execute on macOS host).
  - Force-pushing to `main` (the initial GitHub repo had an auto-generated commit; we did `git pull --rebase -X theirs origin main` to merge instead).

## 15. Suggested Resume Prompt

Paste into a new Claude Code session at `~/slack-summary`:

> Read `handoff.md` first, then inspect the current git state. Continue from the next recommended action. Do not overwrite existing work. Preserve the constraints listed in the handoff.
>
> The Slack daily summarizer project is at a clean stopping point — `main` is at `afb1031`, working tree clean, and the two-section feature (previous business day + since last run) is shipped to https://github.com/justinhlau/pmo-slack-summary. There's no in-flight task. If the user asks for a new feature or fix, start by re-reading `~/slack-summary/run.sh` and `~/slack-summary/prompt.md`, then propose a small targeted change. Confirm with `~/slack-summary/run.sh --dry-run` before any change that touches the prompt or window logic. Do not modify the user's global git config, do not commit on the user's behalf without explicit instruction, and do not regress the `slackdump export` choice or the `<TODAY>.{md,html}` filename convention.
