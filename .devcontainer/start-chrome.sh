#!/usr/bin/env bash
set -e

# Parse arguments for show-errors flag
SHOW_ERRORS=false
CHROME_ARGS=()

for arg in "$@"; do
  if [[ "$arg" == "--show-errors" ]]; then
    SHOW_ERRORS=true
  else
    CHROME_ARGS+=("$arg")
  fi
done

# Set up a dedicated Chrome user profile directory outside the workspace
PROFILE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/chrome-profile"
mkdir -p "$PROFILE_DIR"

# Remove SingletonLock to prevent "profile in use" errors after container restarts
rm -f "$PROFILE_DIR/SingletonLock"

# Clear session restore files to prevent reopening previous tabs
echo "Clearing previous session data..."
rm -rf "$PROFILE_DIR/Default/Sessions"
rm -f "$PROFILE_DIR/Default/Preferences"
rm -f "$PROFILE_DIR/Default/Last Session"
rm -f "$PROFILE_DIR/Default/Last Tabs"
rm -f "$PROFILE_DIR/Default/Current Session"
rm -f "$PROFILE_DIR/Default/Current Tabs"

# Graceful shutdown handler
CHROME_PID=""

cleanup() {
  echo ""
  echo "Shutting down Chrome gracefully..."
  if [[ -n "$CHROME_PID" ]] && kill -0 "$CHROME_PID" 2>/dev/null; then
    kill -TERM "$CHROME_PID" 2>/dev/null
    wait "$CHROME_PID" 2>/dev/null
  fi
  echo "Chrome stopped."
  exit 0
}

# Register the cleanup handler for SIGINT (Ctrl+C) and SIGTERM
trap cleanup SIGINT SIGTERM

# Start Chrome with the specified arguments
echo "Launching Chrome for Testing..."
echo "Press Ctrl+C to stop gracefully."

# Suppress error output unless --show-errors is passed
if [[ "$SHOW_ERRORS" == true ]]; then
  exec 2>&1
else
  exec 2>/dev/null
fi

# Start Chrome in the background and capture its PID
chrome \
  --user-data-dir="$PROFILE_DIR" \
  --remote-debugging-port=9222 \
  --auto-open-devtools-for-tabs \
  --disable-default-apps \
  --disable-dev-shm-usage \
  --disable-infobars \
  --disable-setuid-sandbox \
  --disable-sync \
  --enable-automation \
  --force-dark-mode \
  --hide-crash-restore-bubble \
  --no-default-browser-check \
  --no-first-run \
  --no-sandbox \
  --safebrowsing-disable-auto-update \
  --start-maximized \
  "${CHROME_ARGS[@]}" &

CHROME_PID=$!
echo "Chrome running with PID: $CHROME_PID"

# Wait for Chrome to exit
wait "$CHROME_PID"
