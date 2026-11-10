#!/usr/bin/env bash
# SubagentStop: append one JSON line per finished auto-route delegation (sync or background).
# The launch (PostToolUse) only carries an agent id for background runs, no usage/duration,
# so we wait for completion and compute both from the subagent's own transcript.
exec >/dev/null 2>&1
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -f "$dir/auto-route.stats" ] || exit 0
log="$dir/auto-route.log"
# Early exits after the flag check are recorded as one "ts reason" line in auto-route.err.
fail() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$dir/auto-route.err"; exit 0; }
# jq missing would log on every turn: skip it once any line in the err file already ends in "jq missing" (either hook).
command -v jq >/dev/null || { grep -q 'jq missing$' "$dir/auto-route.err" 2>/dev/null || fail "log-route: jq missing"; exit 0; }
input=$(cat)
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty') || fail "log-route: unparseable hook input"
case "$agent_type" in auto-route:*) ;; *) exit 0 ;; esac
transcript=$(printf '%s' "$input" | jq -r '.agent_transcript_path // empty')
[ -n "$transcript" ] || fail "log-route: no agent_transcript_path"
aid=$(printf '%s' "$input" | jq -r '.agent_id // empty')
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ver=$(jq -r '.version // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null)
for _ in 1 2 3 4 5; do
  [ -s "$transcript" ] && break
  sleep 0.1
done
[ -s "$transcript" ] || fail "log-route: transcript unreadable: $transcript"
effort="${agent_type#auto-route:effort-}"
# ponytail: a message id repeats once per content block with growing usage; the last
# occurrence per id is the final total (group_by is a stable sort, so map(.[-1]) keeps it).
# tokens = the final turn's total (context size), matching Claude Code's own subagent count;
# summing every turn would recount the cached context once per turn.
# out_tokens / new_tokens sum the deduped turns instead: output generated, and fresh input
# (input + cache creation); cache_read_tokens sums cache reads, so stats can estimate cost.
# Route-meta: line from the delegation prompt (first user message); each field is parsed on its
# own, so one bad field (files=many) nulls only itself. files keeps its leading digits (7+ -> 7).
# Values are lowercased and leading whitespace before the label is tolerated.
# goal_hash: djb2 of the lowercased Goal: line, so stats can spot the same goal re-delegated.
# agent_id: SubagentStop can fire repeatedly for one agent with a cumulative transcript; every
# firing appends (no unlocked rewrite) and stats.sh keeps only the last row per agent_id.
line=$(jq -cs --arg effort "$effort" --arg ver "$ver" --arg aid "$aid" --arg sid "$sid" '
  def nn: if . == "" then null else . end;
  (([.[] | select(.type=="user")] | first | .message.content // "")
  | (if type=="array" then map(select(.type=="text") | .text) | join("\n") else tostring end)) as $p
  | ($p | ([capture("(^|\\n)[ \\t]*Route-meta: (?<l>[^\\n]*)").l] | first // "" | ascii_downcase)
  | ([scan("(\\w+)=(\\S+)")] | map({(.[0]): .[1]}) | add // {})) as $m
  | ([$p | capture("(^|\\n)[ \\t]*Goal:[ \\t]*(?<g>[^\\n]*)").g] | first // "" | ascii_downcase | gsub("\\s+"; " ") | gsub("^ | $"; "")) as $g
  | {phase: (if ($m.phase | IN("plan","research","implement","debug","review")) then $m.phase else null end),
     risk: (if ($m.risk | IN("low","med","high")) then $m.risk else null end),
     files: ([($m.files // "") | capture("^(?<n>[0-9]+)").n | tonumber] | first),
     tests: (if ($m.tests | IN("y","n")) then $m.tests else null end),
     retry: (if $m.retry == "1" then true elif $m.retry == "0" then false else null end),
     escalated_from: (if (($m.escalated_from // "") | test("^[a-z]+\\+[a-z]+$")) then $m.escalated_from else null end)} as $meta |
  ([.[] | .timestamp? // empty]) as $ts
  | ([.[] | select(.type=="assistant") | select(.message.usage != null)
      | {id: .message.id, ts: .timestamp, u: .message.usage, model: .message.model}]
     | group_by(.id) | map(.[-1]) | sort_by(.ts)) as $d
  | (($d | last | .model) // null) as $rm
  | {
      ts: (now | todate),
      model: (if $rm == null then null
              elif ($rm | test("opus")) then "opus"
              elif ($rm | test("sonnet")) then "sonnet"
              elif ($rm | test("haiku")) then "haiku"
              elif ($rm | test("fable")) then "fable"
              else null end),
      effort: $effort,
      agent_id: ($aid | nn), session_id: ($sid | nn), plugin_version: ($ver | nn),
      goal_hash: (if $g == "" then null else ($g | explode | reduce .[] as $c (5381; (. * 33 + $c) % 4294967296) | tostring) end),
      phase: $meta.phase, risk: $meta.risk, files: $meta.files, tests: $meta.tests,
      retry: $meta.retry, escalated_from: $meta.escalated_from,
      resolved_model: $rm,
      tokens: (($d | last | .u // null) as $u
               | if $u == null then 0
                 else $u.input_tokens + $u.output_tokens
                      + ($u.cache_creation_input_tokens // 0)
                      + ($u.cache_read_input_tokens // 0) end),
      out_tokens: ($d | map(.u.output_tokens // 0) | add // 0),
      new_tokens: ($d | map((.u.input_tokens // 0) + (.u.cache_creation_input_tokens // 0)) | add // 0),
      cache_creation_tokens: ($d | map(.u.cache_creation_input_tokens // 0) | add // 0),
      cache_read_tokens: ($d | map(.u.cache_read_input_tokens // 0) | add // 0),
      duration_ms: (if ($ts | length) > 1
                    then (try ((($ts | max | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
                               - ($ts | min | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) * 1000) catch 0)
                    else 0 end)
    }
' "$transcript") || fail "log-route: jq failed on transcript"
if [ -n "$line" ]; then
  mkdir -p "$(dirname "$log")"
  printf '%s\n' "$line" >> "$log"
fi
exit 0
