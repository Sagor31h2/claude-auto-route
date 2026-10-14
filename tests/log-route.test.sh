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
assert "out_tokens = deduped sum of output" "$(jq -r .out_tokens "$log")" "70"
assert "new_tokens = deduped input + cache creation" "$(jq -r .new_tokens "$log")" "105"
assert "cache_read_tokens = deduped sum of cache reads" "$(jq -r .cache_read_tokens "$log")" "500"
assert "duration_ms from first/last transcript timestamp" "$duration" "90000"

# non-auto-route agent -> must be ignored (no new line)
payload "Explore" | bash "$HOOK"
lines2=$(wc -l < "$log" | tr -d ' ')
assert "non-auto-route agent ignored" "$lines2" "1"

# stats.sh renders the route, run count, tokens and avg seconds
stats_out=$(bash "$STATS")
echo "$stats_out"
case "$stats_out" in
  *"sonnet + high"*"1 runs"*"523 tokens"*"median 90s p90 90s"*"out 70"*"~\$0.001 (approx)"*) echo "PASS: stats.sh output (out + approx cost)" ;;
  *) echo "FAIL: stats.sh output did not match (got: $stats_out)"; fail=1 ;;
esac

# stats.sh ignores empty and corrupt lines without erroring
printf '\n{"malformed json\n' >> "$log"
stats_out2=$(bash "$STATS")
case "$stats_out2" in
  *"sonnet + high"*"1 runs"*"523 tokens"*"median 90s p90 90s"*) echo "PASS: stats.sh skips malformed lines" ;;
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

# Route-meta parsing: present (string content), missing, malformed, block-array content
meta_row() { # $1 = user message content as JSON; logs one row and prints it
  local tr="$WORK/meta.jsonl"
  jq -nc --argjson c "$1" '{type:"user",timestamp:"2026-01-01T00:00:00.000Z",message:{role:"user",content:$c}}' > "$tr"
  echo '{"type":"assistant","timestamp":"2026-01-01T00:00:10.000Z","message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":1,"output_tokens":1}}}' >> "$tr"
  jq -nc --arg t "$tr" '{agent_type:"auto-route:effort-medium", agent_transcript_path:$t}' | bash "$HOOK"
  tail -n 1 "$log"
}
meta_fields='[.phase,.risk,.files,.tests,.retry,.escalated_from]'
row=$(meta_row '"Route-meta: phase=implement risk=med files=3 tests=y retry=1 escalated_from=sonnet+low\nGoal: x"')
assert "meta present" "$(echo "$row" | jq -c "$meta_fields")" '["implement","med",3,"y",true,"sonnet+low"]'
row=$(meta_row '[{"type":"text","text":"Route-meta: phase=plan risk=low files=0 tests=n retry=0 escalated_from=none\nGoal: x"}]')
assert "meta present (block content), none -> null" "$(echo "$row" | jq -c "$meta_fields")" '["plan","low",0,"n",false,null]'
row=$(meta_row '"Goal: no meta line"')
assert "meta missing -> nulls" "$(echo "$row" | jq -c "$meta_fields")" '[null,null,null,null,null,null]'
assert "meta missing keeps other fields" "$(echo "$row" | jq -r '"\(.model) \(.effort)"')" "sonnet medium"
row=$(meta_row '"Route-meta: phase=bogus risk=low files=x tests=y retry=0"')
assert "meta malformed -> nulls" "$(echo "$row" | jq -c "$meta_fields")" '[null,null,null,null,null,null]'

row=$(meta_row '"  Route-meta: phase=Plan risk=Low files=1 tests=Y retry=0 escalated_from=none\nGoal: x"')
assert "meta capitalized + leading space accepted" "$(echo "$row" | jq -c "$meta_fields")" '["plan","low",1,"y",false,null]'
row=$(meta_row '"Route-meta: phase=plan risk=low files=1 tests=n retry=0 escalated_from=bogus"')
assert "bad escalated_from -> nulls" "$(echo "$row" | jq -c "$meta_fields")" '[null,null,null,null,null,null]'
row=$(meta_row '"Route-meta: phase=plan risk=low files=7+ tests=n retry=0 escalated_from=none"')
assert "files=7+ -> nulls" "$(echo "$row" | jq -c "$meta_fields")" '[null,null,null,null,null,null]'

# stats on old rows (no new fields) + new rows: inline excluded from tokens, escalation + phases shown
log_old="$CLAUDE_CONFIG_DIR/auto-route.log"
: > "$log_old"
cat >> "$log_old" <<'EOFL'
{"ts":"t","model":"sonnet","effort":"high","resolved_model":"x","tokens":100,"duration_ms":10000}
{"ts":"t","model":"sonnet","effort":"high","phase":"implement","risk":"low","files":1,"tests":"y","retry":false,"escalated_from":null,"tokens":200,"duration_ms":30000}
{"ts":"t","model":"sonnet","effort":"high","phase":"debug","risk":"high","files":2,"tests":"n","retry":true,"escalated_from":"sonnet+medium","tokens":300,"duration_ms":50000}
{"ts":"t","model":"sonnet","effort":"inline","phase":"inline","tokens":5000,"duration_ms":0}
{"ts":"t","model":"sonnet","effort":"inline","tokens":7000,"duration_ms":0}
EOFL
stats_out3=$(bash "$STATS")
echo "$stats_out3"
case "$stats_out3" in
  *"sonnet + high"*"3 runs"*"600 tokens"*"median 30s p90 50s"*) echo "PASS: stats delegated totals exclude inline" ;;
  *) echo "FAIL: stats delegated line (got: $stats_out3)"; fail=1 ;;
esac
case "$stats_out3" in
  *"inline"*"2 turns"*"median 6000 tokens (context size, not cost)"*) echo "PASS: stats inline line" ;;
  *) echo "FAIL: stats inline line"; fail=1 ;;
esac
case "$stats_out3" in
  *"escalation: 1/2"*"debug: sonnet+high 1"*"implement: sonnet+high 1"*"meta: 2/3 delegated"*) echo "PASS: stats escalation + per-phase routes + meta coverage" ;;
  *) echo "FAIL: stats escalation/phases"; fail=1 ;;
esac
# old rows only: no escalation/phases lines, no error
printf '%s\n' '{"ts":"t","model":"sonnet","effort":"low","tokens":1,"duration_ms":1000}' > "$log_old"
case "$(bash "$STATS")" in
  *"sonnet + low"*escalation*|*phases*) echo "FAIL: stats showed meta lines for old rows"; fail=1 ;;
  *"sonnet + low"*"1 runs"*) echo "PASS: stats old rows only" ;;
  *) echo "FAIL: stats old rows only"; fail=1 ;;
esac

# escalated away + mismatch + out/cost; rows lacking out_tokens/new_tokens skip out and cost
cat > "$log_old" <<'EOFL'
{"ts":"t","model":"sonnet","effort":"low","phase":"implement","risk":"high","files":1,"tests":"y","retry":false,"escalated_from":null,"tokens":1,"duration_ms":1000}
{"ts":"t","model":"sonnet","effort":"low","phase":"implement","risk":"med","files":1,"tests":"y","retry":false,"escalated_from":null,"tokens":1,"duration_ms":1000}
{"ts":"t","model":"sonnet","effort":"medium","phase":"debug","risk":"med","files":1,"tests":"y","retry":true,"escalated_from":"sonnet+low","tokens":1,"duration_ms":1000}
{"ts":"t","model":"opus","effort":"high","phase":"debug","risk":"low","files":1,"tests":"y","retry":false,"escalated_from":null,"tokens":1,"duration_ms":1000,"out_tokens":1000000,"new_tokens":1000000}
EOFL
o=$(bash "$STATS"); echo "$o"
case "$o" in *"escalated away: sonnet+low 1/2 (50%)"*) echo "PASS: escalated away" ;; *) echo "FAIL: escalated away"; fail=1 ;; esac
case "$o" in *"mismatch: high-risk on low/medium effort 1, low-risk on high/xhigh effort 1"*) echo "PASS: mismatch" ;; *) echo "FAIL: mismatch"; fail=1 ;; esac
case "$o" in *"opus + high"*"out 1000000"*'~$24 (approx, old rows lack cache reads)'*) echo "PASS: cost estimate" ;; *) echo "FAIL: cost estimate"; fail=1 ;; esac
case "$(grep '^sonnet + low' <<<"$o")" in *out*|*approx*) echo "FAIL: out/cost shown for rows lacking fields"; fail=1 ;; *) echo "PASS: no out/cost without fields" ;; esac
printf '%s\n' '{"ts":"t","model":"sonnet","effort":"low","phase":"plan","risk":"low","retry":false,"escalated_from":null,"tokens":1,"duration_ms":1000}' > "$log_old"
case "$(bash "$STATS")" in *"escalated away"*|*mismatch*) echo "FAIL: lines shown without data"; fail=1 ;; *) echo "PASS: escalated/mismatch omitted when none" ;; esac

# cache reads costed: sonnet 1M cache reads at $0.20 = $0.2; all rows carry it -> plain (approx)
printf '%s\n' '{"ts":"t","model":"sonnet","effort":"low","tokens":1,"duration_ms":1000,"out_tokens":0,"new_tokens":0,"cache_read_tokens":1000000}' > "$log_old"
case "$(bash "$STATS")" in *'~$0.2 (approx)'*) echo "PASS: cache read cost" ;; *) echo "FAIL: cache read cost"; fail=1 ;; esac

# slow line: 1 of 2 sonnet+high runs over 600s; omitted when none
cat > "$log_old" <<'EOFL'
{"ts":"t","model":"sonnet","effort":"high","tokens":1,"duration_ms":601000}
{"ts":"t","model":"sonnet","effort":"high","tokens":1,"duration_ms":600000}
{"ts":"t","model":"sonnet","effort":"inline","tokens":1,"duration_ms":900000}
EOFL
case "$(bash "$STATS")" in *"slow (>10min): sonnet+high 1/2 (50%)"*) echo "PASS: slow line" ;; *) echo "FAIL: slow line"; fail=1 ;; esac
printf '%s\n' '{"ts":"t","model":"sonnet","effort":"high","tokens":1,"duration_ms":600000}' > "$log_old"
case "$(bash "$STATS")" in *slow*) echo "FAIL: slow shown when none"; fail=1 ;; *) echo "PASS: slow omitted when none" ;; esac

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
