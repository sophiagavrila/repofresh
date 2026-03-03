# repofresh

Keep every repo in a workspace directory up-to-date so your AI coding tools always query the latest code.

## The Problem

If you work across many repositories (10, 30, 50+), they drift out of date fast. Every morning your local copies are stale. This causes two problems:

1. **Your code is old.** You're reading yesterday's (or last week's) version of files that teammates have already changed.
2. **Your AI tools are blind.** Tools like [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [GitHub Copilot](https://github.com/features/copilot), [Cursor](https://cursor.sh), or any coding agent that indexes local files will search, suggest, and answer questions based on outdated code. If you use a local search index like [QMD](https://github.com/tobi/qmd), it's only as fresh as the files on disk.

## The Solution

`repofresh` walks every subdirectory in your workspace, pulls the latest default branch (`main` or `master`) for each git repo, then optionally re-indexes your local search tool. A companion macOS prompt asks for your approval each morning so nothing runs without you knowing.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What's in the Box](#whats-in-the-box)
- [How the Sync Works](#how-the-sync-works)
- [Daily Prompt (macOS)](#daily-prompt-macos)
- [Running Manually](#running-manually)
- [Checking Logs](#checking-logs)
- [Customization](#customization)
- [Safety Guarantees](#safety-guarantees)
- [Using with AI Coding Tools](#using-with-ai-coding-tools)
- [Uninstalling](#uninstalling)
- [License](#license)

---

## Quick Start

### 1. Clone this repo

```bash
git clone https://github.com/sophiagavrila/repofresh.git ~/repofresh
```

### 2. Set your workspace path

Open `repofresh.sh` and change the `WORKSPACE_DIR` default on line 19 to the directory that contains all your repos:

```bash
WORKSPACE_DIR="${WORKSPACE_DIR:-/path/to/your/workspace}"
```

### 3. Make the scripts executable

```bash
chmod +x ~/repofresh/repofresh.sh
chmod +x ~/repofresh/repofresh-prompt.sh
```

### 4. Run it

```bash
~/repofresh/repofresh.sh
```

That's it. Every git repo inside your workspace directory gets pulled to the latest.

### 5. (Optional) Schedule the daily prompt

If you want macOS to ask you each morning at 9 AM whether to sync, see [Daily Prompt](#daily-prompt-macos).

---

## What's in the Box

Nothing is installed globally. The repo contains three files:

| File | What it does |
|------|-------------|
| `repofresh.sh` | The sync script. Pulls every repo and optionally re-indexes your search tool. Run directly whenever you want. |
| `repofresh-prompt.sh` | A wrapper that shows a native macOS dialog for your approval, then runs `repofresh.sh` in a Terminal window if you click "Sync Now". |
| `com.repofresh.plist` | A macOS `launchd` agent config. When loaded, it triggers `repofresh-prompt.sh` at 9:00 AM every day. |

Logs are written to `.repofresh-logs/` inside your workspace directory. They auto-rotate and keep the last 14 days.

---

## How the Sync Works

For **each subdirectory** in your workspace that contains a `.git` folder:

```
1. Detect the default branch
   Reads origin/HEAD, falls back to checking origin/main, then origin/master

2. Stash uncommitted changes (if any)

3. Pull the default branch
   ├─ ON the default branch:     git pull --ff-only origin main
   └─ On a FEATURE branch:       git fetch origin main:main
      (updates the local main ref WITHOUT switching your branch or touching your files)

4. Restore stashed changes

5. Report: PULL (new commits), no output (already current), SKIP, or FAIL
```

After all repos are processed, if [QMD](https://github.com/tobi/qmd) is installed, it runs `qmd update` to re-index changed files. If QMD is not installed, this step is silently skipped — the git sync works on its own.

---

## Daily Prompt (macOS)

Instead of running silently in the background, the daily prompt gives you a native macOS dialog at 9:00 AM:

> **repofresh**
>
> Pull latest code for all workspace repos and re-index?
>
> `[ Skip ]`  `[ Sync Now ]`

- **Sync Now** — opens a Terminal window showing real-time progress
- **Skip** — nothing happens
- The dialog auto-dismisses after 5 minutes if you don't respond

### Setting it up

**1. Copy the plist into your LaunchAgents folder:**

```bash
cp ~/repofresh/com.repofresh.plist ~/Library/LaunchAgents/
```

**2. Edit the plist** — update the file paths inside to match where you cloned `repofresh` and where your workspace lives. The comments in the file tell you which lines to change.

**3. Load the agent:**

```bash
launchctl load ~/Library/LaunchAgents/com.repofresh.plist
```

**4. Test it right now:**

```bash
launchctl start com.repofresh
```

You should see the approval dialog pop up.

### Changing the schedule

Edit `StartCalendarInterval` in the plist. For example, to run at 8:30 AM:

```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>8</integer>
    <key>Minute</key>
    <integer>30</integer>
</dict>
```

Then reload:

```bash
launchctl unload ~/Library/LaunchAgents/com.repofresh.plist
launchctl load ~/Library/LaunchAgents/com.repofresh.plist
```

### Why launchd instead of cron?

macOS `launchd` is the native scheduler. Unlike cron, if your Mac is asleep at 9 AM, launchd fires the job when your machine wakes up. It integrates with macOS power management and doesn't need a separate daemon.

---

## Running Manually

You don't need the daily prompt. Run the script directly anytime:

```bash
# Full sync: pull all repos + re-index
~/repofresh/repofresh.sh

# Pull repos only, skip the search index update
~/repofresh/repofresh.sh --git-only

# Re-index only, skip git pulls
~/repofresh/repofresh.sh --qmd-only
```

Override the workspace directory without editing the script:

```bash
WORKSPACE_DIR=~/projects ~/repofresh/repofresh.sh
```

---

## Checking Logs

Each run creates a timestamped log file in `.repofresh-logs/` inside your workspace:

```bash
# View the most recent log
ls -t ~/workspace/.repofresh-logs/repofresh-*.log | head -1 | xargs cat

# View launchd-level output (if the prompt itself has issues)
cat ~/workspace/.repofresh-logs/launchd-stdout.log
```

### Example output

```
=== repofresh started at Tue Mar  3 09:00:01 PST 2026 ===
    Workspace: /Users/you/workspace

  PULL  vulnerability-aggregator (main) a1b2c3d → e4f5g6h
  PULL  wiz-therapy (main) 1234567 → 89abcde
  PULL  token-scanning-service (main) fedcba9 → 8765432

--- Git sync complete ---
    Total repos:  53
    Updated:      3
    No changes:   49
    Skipped:      0
    Failed:       1

--- Updating search index ---
...

--- Index update complete ---

=== repofresh finished at Tue Mar  3 09:01:45 PST 2026 ===
```

| Status | Meaning |
|--------|---------|
| `PULL` | New commits were fetched from origin |
| *(no output)* | Repo was already up-to-date |
| `SKIP` | Could not determine the default branch |
| `FAIL` | `git pull` or `git fetch` failed (network issue, local divergence, etc.) |
| `WARN` | Stash pop failed — your changes are still safe in `git stash list` |

---

## Customization

### Different workspace directory

Set the `WORKSPACE_DIR` environment variable, or edit the default at the top of `repofresh.sh`:

```bash
WORKSPACE_DIR="${WORKSPACE_DIR:-/your/path/here}"
```

### Different search index tool

The script calls `qmd update` at the end by default. To use a different indexing tool, replace the block near the bottom of `repofresh.sh`:

```bash
if [ "$INDEX_UPDATE" = true ]; then
  # Replace with your indexing command
  your-index-tool rebuild
fi
```

Or use `--git-only` and run your own indexing separately.

### Log retention

Change `MAX_LOGS=14` at the top of `repofresh.sh` to keep more or fewer days of history.

---

## Safety Guarantees

This script is designed to never damage your work:

| Guarantee | How |
|-----------|-----|
| **Never creates merge commits** | Uses `git pull --ff-only`. If the pull can't fast-forward, it fails gracefully. |
| **Never switches your branch** | If you're on a feature branch, uses `git fetch origin main:main` to update the local `main` ref without touching your checked-out files. |
| **Never drops uncommitted changes** | Stashes before any git operation and restores after. If stash pop fails, changes remain safe in `git stash list`. |
| **Never runs destructive commands** | No `git reset`, `git checkout .`, `git clean`, or `--force` anything. |
| **Never pushes** | Read-only. Only fetches and pulls from origin. |

---

## Using with AI Coding Tools

The whole point of keeping repos fresh is so your AI tools see current code. Here's how this helps different setups:

### Claude Code

Claude Code reads files directly from your filesystem. Fresh repos mean Claude sees the latest code when you ask questions or request changes across repositories.

### QMD (local hybrid search index)

If you use [QMD](https://github.com/tobi/qmd) to index repos for hybrid search (BM25 + vector + LLM reranking), repofresh runs `qmd update` after pulling to re-index changed files. Your search results always reflect the latest `main`.

### GitHub Copilot / Cursor / Windsurf / Other Agents

Any AI tool that reads your local workspace benefits from fresh files. Run repofresh before starting your workday and every tool that touches your codebase is working with current code.

### The general principle

**Local files are the source of truth for local AI tools.** If your files are stale, your AI is stale. repofresh keeps them current.

---

## Uninstalling

```bash
# Remove the daily prompt
launchctl unload ~/Library/LaunchAgents/com.repofresh.plist
rm ~/Library/LaunchAgents/com.repofresh.plist

# Remove repofresh
rm -rf ~/repofresh

# Remove logs from your workspace
rm -rf ~/workspace/.repofresh-logs
```

---

## License

MIT
