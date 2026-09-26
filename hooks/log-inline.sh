#!/usr/bin/env bash
# Stop: log one line per turn the main session answered with "Route: inline",
# so stats.sh also reflects inline routes instead of only delegated subagent runs.
exec >/dev/null 2>&1
[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.stats" ] || exit 0
command -v jq >/dev/null || exit 0
log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty') || exit 0
[ -s "$transcript" ] || exit 0

# Last assistant message's text blocks joined; only the final turn is checked, so a
# non-inline turn (or one with no text, e.g. pure tool calls) never gets logged.
line=$(jq -cs '
  ([.[] | select(.type=="assistant")] | last) as $m
  | ($m.message.content // [] | map(select(.type=="text") | .text) | join("\n")) as $text
  | if ($text | test("(^|\n)Route: inline")) then
      ($m.message.model // null) as $rm
      | ($m.message.usage) as $u
      | {
          ts: (now | todate),
          model: (if $rm == null then null
                  elif ($rm | test("opus")) then "opus"
                  elif ($rm | test("sonnet")) then "sonnet"
                  elif ($rm | test("haiku")) then "haiku"
                  elif ($rm | test("fable")) then "fable"
                  else null end),
          effort: "inline",
          resolved_model: $rm,
          tokens: (if $u == null then 0
                   else $u.input_tokens + $u.output_tokens
                        + ($u.cache_creation_input_tokens // 0)
                        + ($u.cache_read_input_tokens // 0) end),
          duration_ms: 0
        }
    else empty end
' "$transcript") || exit 0
if [ -n "$line" ]; then
  mkdir -p "$(dirname "$log")"
  printf '%s\n' "$line" >> "$log"
fi
exit 0
