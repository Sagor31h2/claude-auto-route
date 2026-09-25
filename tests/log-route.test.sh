#!/usr/bin/env bash
# Runnable test for hooks/log-route.sh (SubagentStop) + skills/auto-route/stats.sh.
# Uses a fake hook payload and a fake subagent transcript fixture with a duplicated
# message id (simulating the real transcript format, where a message repeats once
# per content block with growing usage). Writes only under a temp CLAUDE_CONFIG_DIR.
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$SCRIPT_DIR/.."
HOOK="$ROOT/hooks/log-route.sh"
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

transcript="$WORK/agent-fake.jsonl"
cat > "$transcript" <<'EOF'
{"type":"user","timestamp":"2026-01-01T00:00:00.000Z","message":{"role":"user","content":"go"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:10.000Z","message":{"id":"msg_A","model":"claude-sonnet-5","usage":{"input_tokens":2,"output_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":0}}}
{"type":"assistant","timestamp":"2026-01-01T00:00:20.000Z","message":{"id":"msg_A","model":"claude-sonnet-5","usage":{"input_tokens":2,"output_tokens":50,"cache_creation_input_tokens":100,"cache_read_input_tokens":0}}}
{"type":"user","timestamp":"2026-01-01T00:00:30.000Z","message":{"role":"user","content":"more"}}
{"type":"assistant","timestamp":"2026-01-01T00:01:30.000Z","message":{"id":"msg_B","model":"claude-sonnet-5","usage":{"input_tokens":3,"output_tokens":20,"cache_read_input_tokens":500}}}
EOF
# msg_A repeats once per content block (5->50 output tokens); a correct dedupe keeps only
# the final (last) occurrence: 2+50+100+0=152. msg_B has no cache_creation_input_tokens
# (tests the `// 0` default): 3+20+0+500=523. Logged tokens = final turn (msg_B) = 523;
# a sum over turns would give 675, a sum without dedupe 782.
# Duration: last ts (00:01:30) - first ts (00:00:00) = 90000ms.

payload() {
  jq -nc --arg t "$transcript" --arg at "$1" \
    '{agent_id:"fake1", agent_type:$at, agent_transcript_path:$t, session_id:"s1", hook_event_name:"SubagentStop"}'
}

# auto-route agent -> should log one line
payload "auto-route:effort-high" | bash "$HOOK"

log="$CLAUDE_CONFIG_DIR/auto-route.log"
[ -f "$log" ] || { echo "FAIL: log file was not created"; exit 1; }

lines=$(wc -l < "$log" | tr -d ' ')
assert "one line logged for auto-route agent" "$lines" "1"

read -r model effort resolved tokens duration <<EOF2
$(jq -r '"\(.model) \(.effort) \(.resolved_model) \(.tokens) \(.duration_ms)"' "$log")
EOF2
assert "model alias" "$model" "sonnet"
assert "effort" "$effort" "high"
assert "resolved_model" "$resolved" "claude-sonnet-5"
assert "tokens = final turn total" "$tokens" "523"
assert "duration_ms from first/last transcript timestamp" "$duration" "90000"

# non-auto-route agent -> must be ignored (no new line)
payload "Explore" | bash "$HOOK"
lines2=$(wc -l < "$log" | tr -d ' ')
assert "non-auto-route agent ignored" "$lines2" "1"

# stats.sh renders the route, run count, tokens and avg seconds
stats_out=$(bash "$STATS")
echo "$stats_out"
case "$stats_out" in
  *"sonnet + high"*"1 runs"*"523 tokens"*"90s avg"*) echo "PASS: stats.sh output" ;;
  *) echo "FAIL: stats.sh output did not match (got: $stats_out)"; fail=1 ;;
esac

# stats.sh ignores empty and corrupt lines without erroring
printf '\n{"malformed json\n' >> "$log"
stats_out2=$(bash "$STATS")
case "$stats_out2" in
  *"sonnet + high"*"1 runs"*"523 tokens"*"90s avg"*) echo "PASS: stats.sh skips malformed lines" ;;
  *) echo "FAIL: stats.sh did not handle malformed lines (got: $stats_out2)"; fail=1 ;;
esac

# irregular timestamps with timezone offset: duration falls back to 0 without discarding entry
transcript_tz="$WORK/agent-tz.jsonl"
cat > "$transcript_tz" <<'EOFTZ'
{"type":"user","timestamp":"2026-01-01T00:00:00+02:00","message":{"role":"user","content":"go"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:10+02:00","message":{"id":"msg_TZ","model":"claude-3-5-haiku-20241022","usage":{"input_tokens":10,"output_tokens":20}}}
EOFTZ
jq -nc --arg t "$transcript_tz" '{agent_id:"fake2", agent_type:"auto-route:effort-low", agent_transcript_path:$t, session_id:"s2", hook_event_name:"SubagentStop"}' | bash "$HOOK"
read -r m2 e2 dur2 <<EOF3
$(tail -n 1 "$log" | jq -r '"\(.model) \(.effort) \(.duration_ms)"')
EOF3
assert "haiku logged despite tz offset" "$m2" "haiku"
assert "effort-low logged despite tz offset" "$e2" "low"
assert "duration defaulted to 0 on unparseable tz format" "$dur2" "0"

# flag absent -> hook exits before logging, log file not (re)created
WORK2=$(mktemp -d)
CLAUDE_CONFIG_DIR="$WORK2/config" bash -c "payload() { jq -nc --arg t '$transcript' --arg at \"\$1\" '{agent_id:\"fake3\", agent_type:\$at, agent_transcript_path:\$t, session_id:\"s3\", hook_event_name:\"SubagentStop\"}'; }; payload auto-route:effort-high | bash '$HOOK'"
[ -f "$WORK2/config/auto-route.log" ] && { echo "FAIL: log file created without stats flag"; fail=1; } || echo "PASS: no log file without stats flag"
rm -rf "$WORK2"

if [ "$fail" -eq 0 ]; then
  echo "ALL PASS"
  exit 0
else
  echo "SOME FAILED"
  exit 1
fi
