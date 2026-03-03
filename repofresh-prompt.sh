#!/bin/bash
# repofresh-prompt.sh — Shows a macOS dialog asking to sync. Runs repofresh.sh if approved.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/repofresh.sh"

# Show a native macOS approval dialog
RESPONSE=$(osascript -e '
  display dialog "Pull latest code for all workspace repos and re-index?" ¬
    buttons {"Skip", "Sync Now"} ¬
    default button "Sync Now" ¬
    with title "repofresh" ¬
    giving up after 300
' 2>/dev/null)

if echo "$RESPONSE" | grep -q "Sync Now"; then
  # Open a terminal window so user can watch progress
  osascript -e "
    tell application \"Terminal\"
      activate
      do script \"$SYNC_SCRIPT; echo ''; echo 'Press any key to close...'; read -n 1\"
    end tell
  "
fi
