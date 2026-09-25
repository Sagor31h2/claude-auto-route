#!/usr/bin/env bash
# Helper for auto-route admin commands: on, off, status, stats, reset.
set -euo pipefail
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ARG="${1:-}"

# Normalize: lowercase and trim whitespace
cmd=$(printf '%s' "$ARG" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')
cmd="${cmd#"${cmd%%[![:space:]]*}"}"
cmd="${cmd%"${cmd##*[![:space:]]}"}"

case "$cmd" in
  on)
    mkdir -p "$DIR" && touch "$DIR/auto-route.on"
    echo "Auto-route: ON"
    ;;
  off)
    rm -f "$DIR/auto-route.on"
    echo "Auto-route: OFF"
    ;;
  status)
    [ -f "$DIR/auto-route.on" ] && echo "Auto-route: ON" || echo "Auto-route: OFF"
    ;;
  "stats on")
    mkdir -p "$DIR" && touch "$DIR/auto-route.stats"
    echo "Auto-route stats: ON"
    ;;
  "stats off")
    rm -f "$DIR/auto-route.stats"
    echo "Auto-route stats: OFF"
    ;;
  reset)
    rm -f "$DIR/auto-route.log"
    echo "Auto-route stats reset."
    ;;
  stats)
    if [ ! -f "$DIR/auto-route.stats" ]; then
      echo "Stats logging is off. Enable with /auto-route:auto-route stats on."
    fi
    bash "$SCRIPT_DIR/stats.sh"
    ;;
  *)
    echo "Unknown command: $ARG"
    exit 1
    ;;
esac
