#!/usr/bin/env bash
# Helper for auto-route admin commands: on, off, status, stats [since YYYY-MM-DD], reset.
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
    rm -f "$DIR/auto-route.log" "$DIR/auto-route.err"
    echo "Auto-route stats reset."
    ;;
  stats|"stats since"|"stats since "*)
    if [ ! -f "$DIR/auto-route.stats" ]; then
      echo "Stats logging is off. Enable with /auto-route:auto-route stats on."
    fi
    # "stats since YYYY-MM-DD" passes "since YYYY-MM-DD" on; stats.sh validates the date
    set -f
    bash "$SCRIPT_DIR/stats.sh" ${cmd#stats}
    ;;
  *)
    echo "Unknown command: $ARG"
    exit 1
    ;;
esac
