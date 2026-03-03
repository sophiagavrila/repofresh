#!/bin/bash
# repofresh.sh — Pull latest code for all repos and index them with QMD for AI tools.
#
# repofresh does two things:
#   1. Git sync  — pull the latest default branch for every repo in your workspace
#   2. QMD index — register new repos and re-index all code so AI tools can search it
#
# QMD (https://github.com/tobi/qmd) is an on-device search engine that builds a local
# SQLite index of your source code with full-text search (BM25), vector embeddings, and
# LLM reranking. This is what makes your repos instantly queryable by Claude Code,
# Copilot, Cursor, or any coding agent. repofresh installs QMD automatically if needed.
#
# Usage:
#   ./repofresh.sh              # sync all repos + index with QMD
#   ./repofresh.sh --git-only   # sync repos only, skip QMD indexing
#   ./repofresh.sh --index-only # skip git, just re-index with QMD

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspace}"
LOG_DIR="${WORKSPACE_DIR}/.repofresh-logs"
LOG_FILE="${LOG_DIR}/repofresh-$(date +%Y-%m-%d_%H%M%S).log"
MAX_LOGS=14  # Keep 2 weeks of logs

mkdir -p "$LOG_DIR"

# Parse flags
GIT_SYNC=true
INDEX_UPDATE=true
for arg in "$@"; do
  case "$arg" in
    --git-only) INDEX_UPDATE=false ;;
    --index-only) GIT_SYNC=false ;;
    --help|-h)
      echo "Usage: $0 [--git-only | --index-only]"
      echo "  --git-only    Sync repos only, skip QMD indexing"
      echo "  --index-only  Skip git sync, just re-index with QMD"
      exit 0
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Ensure QMD is installed (required for indexing + embedding)
# QMD is an on-device search engine that indexes your code into a local
# SQLite database with full-text search (BM25), vector embeddings, and
# LLM reranking. This is what makes your repos queryable by AI tools.
# ---------------------------------------------------------------------------
ensure_qmd() {
  if command -v qmd &>/dev/null; then
    return 0
  fi

  echo "--- QMD not found. Installing... ---"
  echo ""

  # Prefer bun, fall back to npm
  if command -v bun &>/dev/null; then
    echo "    Installing with bun..."
    bun install -g @tobilu/qmd
  elif command -v npm &>/dev/null; then
    echo "    Installing with npm..."
    npm install -g @tobilu/qmd
  else
    echo "ERROR: Cannot install QMD — neither bun nor npm found."
    echo "       Install Node.js 22+ (https://nodejs.org) or Bun (https://bun.sh),"
    echo "       then run:  npm install -g @tobilu/qmd"
    return 1
  fi

  # Verify installation
  if command -v qmd &>/dev/null; then
    echo "    QMD installed successfully: $(qmd --version 2>/dev/null || echo 'ok')"
    echo ""
    return 0
  else
    echo "ERROR: QMD installation completed but 'qmd' not found in PATH."
    echo "       You may need to restart your shell or add the install path to PATH."
    return 1
  fi
}

# Tee output to both stdout and log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== repofresh started at $(date) ==="
echo "    Workspace: $WORKSPACE_DIR"
echo ""

# Counters
total=0
updated=0
skipped=0
failed=0
no_changes=0

sync_repo() {
  local repo_dir="$1"
  local repo_name
  repo_name=$(basename "$repo_dir")

  # Skip non-git directories
  if [ ! -d "$repo_dir/.git" ]; then
    return
  fi

  total=$((total + 1))

  # Detect the default branch from origin/HEAD
  local default_branch
  default_branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')

  # Fallback: check if main or master exists on origin
  if [ -z "$default_branch" ]; then
    if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
      default_branch="main"
    elif git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
      default_branch="master"
    else
      echo "  SKIP  $repo_name — cannot determine default branch"
      skipped=$((skipped + 1))
      return
    fi
  fi

  # Save current branch (or commit hash if detached)
  local current_branch
  current_branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$current_branch" = "HEAD" ]; then
    current_branch=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)
  fi

  # Check for uncommitted changes
  local had_stash=false
  if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
    git -C "$repo_dir" stash push -q -m "repofresh auto-stash $(date +%Y%m%d)" 2>/dev/null && had_stash=true
  fi

  # Record the commit before pull to detect changes
  local before_sha
  before_sha=$(git -C "$repo_dir" rev-parse "refs/remotes/origin/$default_branch" 2>/dev/null)

  # Fetch + fast-forward the default branch
  local pull_ok=true
  if [ "$current_branch" = "$default_branch" ]; then
    # Already on default branch — just pull
    if ! git -C "$repo_dir" pull --ff-only origin "$default_branch" -q 2>/dev/null; then
      pull_ok=false
    fi
  else
    # On a different branch — fetch and update the local default branch ref without checkout
    if ! git -C "$repo_dir" fetch origin "$default_branch:$default_branch" --update-head-ok -q 2>/dev/null; then
      # fetch into local branch failed (maybe diverged), try regular fetch
      git -C "$repo_dir" fetch origin -q 2>/dev/null || pull_ok=false
    fi
  fi

  # Check if anything changed
  local after_sha
  after_sha=$(git -C "$repo_dir" rev-parse "refs/remotes/origin/$default_branch" 2>/dev/null)

  if [ "$pull_ok" = false ]; then
    echo "  FAIL  $repo_name ($default_branch) — pull/fetch failed"
    failed=$((failed + 1))
  elif [ "$before_sha" != "$after_sha" ]; then
    local short_before=${before_sha:0:7}
    local short_after=${after_sha:0:7}
    echo "  PULL  $repo_name ($default_branch) $short_before → $short_after"
    updated=$((updated + 1))
  else
    no_changes=$((no_changes + 1))
  fi

  # Restore stashed changes
  if [ "$had_stash" = true ]; then
    git -C "$repo_dir" stash pop -q 2>/dev/null || \
      echo "  WARN  $repo_name — stash pop failed, changes saved in stash"
  fi
}

if [ "$GIT_SYNC" = true ]; then
  for repo_dir in "$WORKSPACE_DIR"/*/; do
    sync_repo "$repo_dir"
  done

  echo ""
  echo "--- Git sync complete ---"
  echo "    Total repos:  $total"
  echo "    Updated:      $updated"
  echo "    No changes:   $no_changes"
  echo "    Skipped:      $skipped"
  echo "    Failed:       $failed"
  echo ""
fi

if [ "$INDEX_UPDATE" = true ]; then
  if ensure_qmd; then
    # Auto-register new repos as QMD collections
    QMD_MASK='**/*.{py,go,js,ts,jsx,tsx,java,rs,rb,sh,yaml,yml,toml,json,md,html,css,sql,tf,hcl,Dockerfile,proto,graphql,gql}'
    existing_collections=$(qmd collection list 2>/dev/null | grep -E '^\S' | grep -v '^Collections' | grep -v '^Examples' | sed 's/ .*//')
    new_count=0

    for repo_dir in "$WORKSPACE_DIR"/*/; do
      [ -d "$repo_dir/.git" ] || continue
      repo_name=$(basename "$repo_dir")

      # Check if a collection already exists for this repo
      if ! echo "$existing_collections" | grep -qx "$repo_name"; then
        echo "  NEW   Adding QMD collection: $repo_name"
        qmd collection add "$repo_dir" --name "$repo_name" --mask "$QMD_MASK" 2>&1 | sed 's/^/        /'
        new_count=$((new_count + 1))
      fi
    done

    if [ "$new_count" -gt 0 ]; then
      echo ""
      echo "    Added $new_count new QMD collection(s)"
      echo ""
    fi

    echo "--- Updating QMD search index ---"
    qmd update 2>&1
    echo ""
    echo "--- QMD index update complete ---"
  else
    echo ""
    echo "WARN: QMD could not be installed. Git sync completed but repos are not indexed."
    echo "      Install manually:  npm install -g @tobilu/qmd"
  fi
fi

echo ""
echo "=== repofresh finished at $(date) ==="

# Rotate old logs
find "$LOG_DIR" -name "repofresh-*.log" -type f | sort -r | tail -n +$((MAX_LOGS + 1)) | xargs rm -f 2>/dev/null || true
