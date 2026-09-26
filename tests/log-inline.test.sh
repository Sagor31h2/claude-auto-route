#!/usr/bin/env bash
# Runnable test for hooks/log-inline.sh (Stop) + skills/auto-route/stats.sh.
# Verifies inline "Route: inline" turns get logged (closing the stats blind spot
# where only delegated subagent runs used to show up), and that other turns don't.
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$SCRIPT_DIR/.."
HOOK="$ROOT/hooks/log-inline.sh"
STATS="$ROOT/skills/auto-route/stats.sh"

WORK=$(mktemp -d)
export CLAUDE_CONFIG_DIR="$WORK/config"
mkdir -p "$CLAUDE_CONFIG_DIR"
trap 'rm -rf "$WORK"' EXIT
touch "$CLAUDE_CONFIG_DIR/auto-route.stats"

fail=0
assert() {
  local desc=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (got [$got], want [$want])"
    fail=1
  fi
}

payload() {
  jq -nc --arg t "$1" '{session_id:"s1", transcript_path:$t, hook_event_name:"Stop"}'
}

# 1. Inline turn -> logged with effort "inline" and the resolved model alias
transcript_inline="$WORK/inline.jsonl"
cat > "$transcript_inline" <<'EOF'
{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"user","content":"hi"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:05.000Z","message":{"id":"msg_X","model":"claude-sonnet-5","content":[{"type":"text","text":"Route: inline (pure chat question)\nHello there."}],"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":5}}}
EOF
payload "$transcript_inline" | bash "$HOOK"

log="$CLAUDE_CONFIG_DIR/auto-route.log"
[ -f "$log" ] || { echo "FAIL: log file was not created"; exit 1; }
lines=$(wc -l < "$log" | tr -d ' ')
assert "one line logged for inline turn" "$lines" "1"

read -r model effort tokens <<EOF2
$(jq -r '"\(.model) \(.effort) \(.tokens)"' "$log")
EOF2
assert "model alias" "$model" "sonnet"
assert "effort marked inline" "$effort" "inline"
assert "tokens summed from usage" "$tokens" "35"

# 2. Tool-use turn (no "Route: inline" text) -> must be ignored
transcript_tool="$WORK/tool.jsonl"
cat > "$transcript_tool" <<'EOF'
{"type":"user","timestamp":"2026-01-01T00:01:00.000Z","message":{"role":"user","content":"fix bug"}}
{"type":"assistant","timestamp":"2026-01-01T00:01:05.000Z","message":{"id":"msg_Y","model":"claude-sonnet-5","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}],"usage":{"input_tokens":5,"output_tokens":5}}}
EOF
payload "$transcript_tool" | bash "$HOOK"
lines2=$(wc -l < "$log" | tr -d ' ')
assert "non-inline turn ignored" "$lines2" "1"

# 3. Delegated-route turn ("Route: sonnet + medium (...)") -> must NOT be logged as inline
transcript_delegated="$WORK/delegated.jsonl"
cat > "$transcript_delegated" <<'EOF'
{"type":"user","timestamp":"2026-01-01T00:02:00.000Z","message":{"role":"user","content":"refactor"}}
{"type":"assistant","timestamp":"2026-01-01T00:02:05.000Z","message":{"id":"msg_Z","model":"claude-sonnet-5","content":[{"type":"text","text":"Route: sonnet + effort-medium (standard refactor)"}],"usage":{"input_tokens":5,"output_tokens":5}}}
EOF
payload "$transcript_delegated" | bash "$HOOK"
lines3=$(wc -l < "$log" | tr -d ' ')
assert "delegated-route turn not double-logged as inline" "$lines3" "1"

# 4. stats.sh renders the inline route alongside delegated ones
stats_out=$(bash "$STATS")
case "$stats_out" in
  *"sonnet + inline"*"1 runs"*"35 tokens"*) echo "PASS: stats.sh shows inline route" ;;
  *) echo "FAIL: stats.sh did not show inline route (got: $stats_out)"; fail=1 ;;
esac

# 5. flag absent -> hook exits before logging, log file not (re)created
WORK2=$(mktemp -d)
CLAUDE_CONFIG_DIR="$WORK2/config" bash -c "jq -nc --arg t '$transcript_inline' '{session_id:\"s2\", transcript_path:\$t, hook_event_name:\"Stop\"}' | bash '$HOOK'"
[ -f "$WORK2/config/auto-route.log" ] && { echo "FAIL: log file created without stats flag"; fail=1; } || echo "PASS: no log file without stats flag"
rm -rf "$WORK2"

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
