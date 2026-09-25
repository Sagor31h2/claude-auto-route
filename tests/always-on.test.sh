#!/usr/bin/env bash
# Runnable unit test for hooks/always-on.sh (UserPromptSubmit hook).
# Tests prompt filtering: slash commands, acknowledgements, cancellations, and real tasks.
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$SCRIPT_DIR/.."
HOOK="$ROOT/hooks/always-on.sh"

WORK=$(mktemp -d)
export CLAUDE_CONFIG_DIR="$WORK/config"
mkdir -p "$CLAUDE_CONFIG_DIR"
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

send_prompt() {
  local p=$1
  jq -nc --arg p "$p" '{prompt: $p}' | bash "$HOOK"
}

# 1. When auto-route.on does not exist, nothing should be output
out_disabled=$(send_prompt "Fix typo in README")
assert_eq "disabled when flag file is absent" "$out_disabled" ""

# Enable always-on
touch "$CLAUDE_CONFIG_DIR/auto-route.on"

# 2. Slash commands should be skipped (empty output)
for cmd in "/help" "/exit" "/plugin list" "/auto-route:auto-route stats"; do
  out=$(send_prompt "$cmd")
  assert_eq "slash command skipped: $cmd" "$out" ""
done

# 3. Conversational acknowledgements and pleasantries should be skipped
for ack in "ok" "okay" "yes" "yep" "sure" "continue" "proceed" "done" "lgtm" "looks good" "thanks" "thank you" "great!"; do
  out=$(send_prompt "$ack")
  assert_eq "acknowledgement skipped: $ack" "$out" ""
done

# 4. Conversational cancellations and interruptions should be skipped
for cancel in "no" "stop" "stop!" "cancel" "wait" "hold on" "never mind" "don't do that"; do
  out=$(send_prompt "$cancel")
  assert_eq "cancellation skipped: $cancel" "$out" ""
done

# 5. Real tasks MUST produce the hook directive
for task in "Fix typo in README" "Why does worker pool deadlock?" "Refactor database migrations"; do
  out=$(send_prompt "$task")
  case "$out" in
    *"AUTO-ROUTE ON"*) echo "PASS: task routed: $task" ;;
    *) echo "FAIL: task not routed: $task (got: $out)"; fail=1 ;;
  esac
done

# 6. Tasks starting with ack/cancel words must still be routed
for complex in "continue fixing bug in auth.py" "stop the dev server on port 8080" "cancel pending orders in worker"; do
  out=$(send_prompt "$complex")
  case "$out" in
    *"AUTO-ROUTE ON"*) echo "PASS: multi-word task routed: $complex" ;;
    *) echo "FAIL: multi-word task not routed: $complex (got: $out)"; fail=1 ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
