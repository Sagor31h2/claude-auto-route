#!/usr/bin/env bash
# Runnable unit test for skills/auto-route/manage.sh.
# Tests all subcommands: on, off, status, stats on, stats off, stats, reset.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$SCRIPT_DIR/.."
MANAGE="$ROOT/skills/auto-route/manage.sh"

WORK=$(mktemp -d)
export CLAUDE_CONFIG_DIR="$WORK/config"
trap 'rm -rf "$WORK"' EXIT

fail=0
assert_eq() {
  local desc=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (got [$got], want [$want])"
    fail=1
  fi
}

assert_contains() {
  local desc=$1 haystack=$2 needle=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (needle [$needle] not found in [$haystack])"
    fail=1
  fi
}

# 1. Initial status when flag is absent
out=$(bash "$MANAGE" "status")
assert_eq "initial status is OFF" "$out" "Auto-route: OFF"

# 2. Turn ON
out=$(bash "$MANAGE" "on")
assert_eq "turn on returns Auto-route: ON" "$out" "Auto-route: ON"
[ -f "$CLAUDE_CONFIG_DIR/auto-route.on" ] && echo "PASS: auto-route.on flag created" || { echo "FAIL: flag missing"; fail=1; }

# 3. Status is now ON
out=$(bash "$MANAGE" "status")
assert_eq "status reports ON" "$out" "Auto-route: ON"

# 4. Turn OFF
out=$(bash "$MANAGE" "off")
assert_eq "turn off returns Auto-route: OFF" "$out" "Auto-route: OFF"
[ ! -f "$CLAUDE_CONFIG_DIR/auto-route.on" ] && echo "PASS: auto-route.on flag removed" || { echo "FAIL: flag still exists"; fail=1; }

# 5. Status is now OFF
out=$(bash "$MANAGE" "status")
assert_eq "status reports OFF" "$out" "Auto-route: OFF"

# 6. Turn stats ON
out=$(bash "$MANAGE" "stats on")
assert_eq "stats on returns Auto-route stats: ON" "$out" "Auto-route stats: ON"
[ -f "$CLAUDE_CONFIG_DIR/auto-route.stats" ] && echo "PASS: auto-route.stats flag created" || { echo "FAIL: stats flag missing"; fail=1; }

# 7. Turn stats OFF
out=$(bash "$MANAGE" "stats off")
assert_eq "stats off returns Auto-route stats: OFF" "$out" "Auto-route stats: OFF"
[ ! -f "$CLAUDE_CONFIG_DIR/auto-route.stats" ] && echo "PASS: auto-route.stats flag removed" || { echo "FAIL: stats flag still exists"; fail=1; }

# 8. Stats when flag is off mentions enable command
out=$(bash "$MANAGE" "stats")
assert_contains "stats command warns when off" "$out" "Stats logging is off. Enable with /auto-route:auto-route stats on."

# 9. Reset log file
echo '{"test":1}' > "$CLAUDE_CONFIG_DIR/auto-route.log"
out=$(bash "$MANAGE" "reset")
assert_eq "reset returns Auto-route stats reset." "$out" "Auto-route stats reset."
[ ! -f "$CLAUDE_CONFIG_DIR/auto-route.log" ] && echo "PASS: auto-route.log removed" || { echo "FAIL: log file still exists"; fail=1; }

# 10. Case insensitivity and whitespace trimming
out=$(bash "$MANAGE" "  ON  ")
assert_eq "case insensitive ON" "$out" "Auto-route: ON"
out=$(bash "$MANAGE" "STATS ON")
assert_eq "case insensitive STATS ON" "$out" "Auto-route stats: ON"

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
