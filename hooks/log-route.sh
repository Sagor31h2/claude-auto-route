#!/usr/bin/env bash
# SubagentStop: append one JSON line per finished auto-route delegation (sync or background).
# The launch (PostToolUse) only carries an agent id for background runs, no usage/duration,
# so we wait for completion and compute both from the subagent's own transcript.
exec >/dev/null 2>&1
[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.stats" ] || exit 0
command -v jq >/dev/null || exit 0
log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
input=$(cat)
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty') || exit 0
case "$agent_type" in auto-route:*) ;; *) exit 0 ;; esac
transcript=$(printf '%s' "$input" | jq -r '.agent_transcript_path // empty')
[ -n "$transcript" ] || exit 0
for _ in 1 2 3 4 5; do
  [ -s "$transcript" ] && break
  sleep 0.1
done
[ -s "$transcript" ] || exit 0
effort="${agent_type#auto-route:effort-}"
# ponytail: a message id repeats once per content block with growing usage; the last
# occurrence per id is the final total (group_by is a stable sort, so map(.[-1]) keeps it).
# tokens = the final turn's total (context size), matching Claude Code's own subagent count;
# summing every turn would recount the cached context once per turn.
line=$(jq -cs --arg effort "$effort" '
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
      resolved_model: $rm,
      tokens: (($d | last | .u // null) as $u
               | if $u == null then 0
                 else $u.input_tokens + $u.output_tokens
                      + ($u.cache_creation_input_tokens // 0)
                      + ($u.cache_read_input_tokens // 0) end),
      duration_ms: (if ($ts | length) > 1
                    then (try ((($ts | max | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
                               - ($ts | min | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) * 1000) catch 0)
                    else 0 end)
    }
' "$transcript") || exit 0
if [ -n "$line" ]; then
  mkdir -p "$(dirname "$log")"
  printf '%s\n' "$line" >> "$log"
fi
exit 0
