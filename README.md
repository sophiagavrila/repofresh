# repofresh

Pull the latest code across all your repos and index everything with [QMD](https://github.com/tobi/qmd) so your AI coding tools can search, understand, and reason over your entire codebase — instantly.

## Why This Exists

AI coding tools (Claude Code, GitHub Copilot, Cursor, Windsurf, etc.) are only as smart as the code they can see. If you work across many repositories, two things go wrong:

1. **Your repos drift out of date.** You sit down in the morning and your local copies are a day or a week behind. Your AI agent reads stale files and gives stale answers.

2. **Your AI can't search across repos efficiently.** Even if the files are current, tools that scan the filesystem file-by-file are slow and miss context. You need a search index.

**repofresh solves both problems in one command.** It pulls every repo to the latest, then indexes all source code into a local [QMD](https://github.com/tobi/qmd) database that any AI tool can query in milliseconds.

## What is QMD?

[QMD](https://github.com/tobi/qmd) (Query Markup Documents) is an **on-device search engine** for your source code and documentation. It runs entirely on your machine — no cloud, no API keys, no data leaving your laptop.

**What it builds:** A local SQLite database (`~/.cache/qmd/index.sqlite`) containing every file across all your repos, chunked and indexed three ways:

| Search Method | How it Works | When it Helps |
|---------------|-------------|---------------|
| **Full-text search (BM25)** | Traditional keyword matching, ranked by relevance | "Find all files that reference `VulnerabilityAggregatorClient`" |
| **Vector embeddings** | Each code chunk is converted to a numeric vector that captures its meaning | "Find code that handles authentication failures" (even if it never uses the word "authentication") |
| **LLM reranking** | A small local model re-scores results for the best final ordering | Combines keyword + semantic results into one high-quality ranked list |

**What this means for your AI tools:**

- **Claude Code / Copilot / Cursor** can search 50+ repos in milliseconds instead of scanning the filesystem
- **Semantic search** finds relevant code even when you don't know the exact function name or variable
- **Everything stays local** — your code never leaves your machine
- **Always fresh** — repofresh re-indexes after every pull so the index matches the latest `main`

QMD also exposes an [MCP server](https://github.com/tobi/qmd#mcp-server) so AI tools can query the index directly via the Model Context Protocol.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What's in the Box](#whats-in-the-box)
- [How It Works](#how-it-works)
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

### Prerequisites

- **Git** (you already have this)
- **Node.js 22+** or **Bun** — needed to run QMD. If QMD isn't installed, repofresh installs it automatically via `npm install -g @tobilu/qmd` or `bun install -g @tobilu/qmd`.

### 1. Clone this repo

```bash
git clone https://github.com/sophiagavrila/repofresh.git ~/repofresh
```

### 2. Set your workspace path

Open `repofresh.sh` and change line 19 to the directory that contains all your repos:

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

On first run, repofresh will:

1. Install QMD if it's not already on your machine
2. Pull the latest default branch (`main` or `master`) for every git repo in your workspace
3. Register each repo as a QMD collection
4. Index all source code files into the local QMD database

After this, every repo in your workspace is searchable:

```bash
# Keyword search across all repos
qmd search "authentication middleware"

# Semantic search (finds conceptually related code)
qmd vsearch "how are API errors handled"

# Deep search with query expansion + reranking (best quality)
qmd query "vulnerability notification routing logic"
```

### 5. (Optional) Schedule the daily prompt

If you want macOS to ask you each morning at 9 AM whether to sync, see [Daily Prompt](#daily-prompt-macos).

---

## What's in the Box

Nothing is installed globally except QMD itself (on first run). The repo contains three files:

| File | What it does |
|------|-------------|
| `repofresh.sh` | The main script. Installs QMD if needed, pulls every repo, registers new repos as QMD collections, and re-indexes everything. |
| `repofresh-prompt.sh` | A wrapper that shows a native macOS approval dialog, then runs `repofresh.sh` in a Terminal window if you click "Sync Now". |
| `com.repofresh.plist` | A macOS `launchd` agent config. When loaded, it triggers `repofresh-prompt.sh` at 9:00 AM every day. |

Logs are written to `.repofresh-logs/` inside your workspace directory. They auto-rotate and keep the last 14 days.

---

## How It Works

### Step 1: Git Sync

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

### Step 2: QMD Indexing

After all repos are pulled:

1. **Install QMD** if it's not already installed (via npm or bun)
2. **Auto-detect new repos** — any git repo in the workspace that doesn't have a matching QMD collection gets registered automatically
3. **Re-index all collections** — runs `qmd update` to parse changed files into the search database

The file mask for auto-registered collections covers all common source code and config file types:

```
**/*.{py,go,js,ts,jsx,tsx,java,rs,rb,sh,yaml,yml,toml,json,md,html,css,sql,tf,hcl,Dockerfile,proto,graphql,gql}
```

### What gets indexed vs. what gets skipped

QMD indexes source code, documentation, and configuration. It automatically skips `node_modules/`, `.git/`, `vendor/`, `dist/`, `build/`, and other generated directories.

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
# Full sync: pull all repos + index with QMD
~/repofresh/repofresh.sh

# Pull repos only, skip QMD indexing
~/repofresh/repofresh.sh --git-only

# Re-index with QMD only, skip git pulls
~/repofresh/repofresh.sh --index-only
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
  NEW   Adding QMD collection: my-new-repo
  PULL  token-scanning-service (main) fedcba9 → 8765432

--- Git sync complete ---
    Total repos:  54
    Updated:      3
    No changes:   50
    Skipped:      0
    Failed:       1

    Added 1 new QMD collection(s)

--- Updating QMD search index ---
Updating 54 collection(s)...
...

--- QMD index update complete ---

=== repofresh finished at Tue Mar  3 09:01:45 PST 2026 ===
```

| Status | Meaning |
|--------|---------|
| `PULL` | New commits were fetched from origin |
| `NEW` | A repo was auto-registered as a new QMD collection |
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

### Vector embeddings

After repofresh indexes your files, you can optionally generate vector embeddings for semantic search:

```bash
qmd embed
```

This runs a local embedding model (embeddinggemma, ~300MB) on your machine to convert each code chunk into a vector. It takes a while on first run but is incremental after that — only new/changed chunks get embedded. Once embedded, `qmd vsearch` and `qmd query` return dramatically better results.

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

### Claude Code

Claude Code reads files directly from your filesystem. With QMD indexed repos, you can also connect QMD as an [MCP server](https://github.com/tobi/qmd#mcp-server) so Claude can search across all your repos semantically — not just by filename or grep. Add to your Claude Code config:

```bash
claude mcp add qmd -- qmd mcp
```

### GitHub Copilot / Cursor / Windsurf

Any tool that reads your local workspace benefits from fresh files. Tools that support MCP can connect to QMD's MCP server for cross-repo semantic search. Tools without MCP support still benefit because the repos on disk are current.

### The general principle

**Local files are the source of truth for local AI tools.** If your files are stale, your AI is stale. If your files aren't indexed, your AI has to scan every file on every query.

repofresh keeps the files current. QMD makes them searchable. Together, your AI tools can reason over your entire codebase — across 50+ repos — in milliseconds.

---

## Uninstalling

```bash
# Remove the daily prompt
launchctl unload ~/Library/LaunchAgents/com.repofresh.plist
rm ~/Library/LaunchAgents/com.repofresh.plist

# Remove repofresh
rm -rf ~/repofresh

# Remove QMD and its index
npm uninstall -g @tobilu/qmd
rm -rf ~/.cache/qmd

# Remove logs from your workspace
rm -rf ~/workspace/.repofresh-logs
```

---

## License

MIT
