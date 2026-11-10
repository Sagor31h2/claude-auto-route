#!/usr/bin/env bash
# Stop: log one line per turn the main session answered with "Route: inline",
# so stats.sh also reflects inline routes instead of only delegated subagent runs.
exec >/dev/null 2>&1
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -f "$dir/auto-route.stats" ] || exit 0
log="$dir/auto-route.log"
# Early exits after the flag check are recorded as one "ts reason" line in auto-route.err.
fail() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$dir/auto-route.err"; exit 0; }
# jq missing would log on every turn: skip it once any line in the err file already ends in "jq missing" (either hook).
command -v jq >/dev/null || { grep -q 'jq missing$' "$dir/auto-route.err" 2>/dev/null || fail "log-inline: jq missing"; exit 0; }
input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty') || fail "log-inline: unparseable hook input"
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -s "$transcript" ] || fail "log-inline: transcript unreadable: $transcript"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ver=$(jq -r '.version // empty' "$root/.claude-plugin/plugin.json" 2>/dev/null)

# Last assistant message's text blocks joined; only the final turn is checked, so a
# non-inline turn (or one with no text, e.g. pure tool calls) never gets logged.
# msg_id (the final message's id) lets a repeated Stop on the same message be skipped below.
line=$(jq -cs --arg ver "$ver" --arg sid "$sid" '
  ([.[] | select(.type=="assistant")] | last) as $m
  | ($m.message.content // [] | map(select(.type=="text") | .text) | join("\n")) as $text
  | if ($text | test("(^|\n)Route: inline")) then
      ($m.message.model // null) as $rm
      | ($m.message.usage) as $u
      # reason from "Route: inline (<reason>)", capped at 80 chars; null if absent/unparseable
      | ([$text | capture("(^|\n)Route: inline \\((?<r>[^)\n]+)\\)").r | .[:80]] | first // null) as $reason
      | {
          ts: (now | todate),
          model: (if $rm == null then null
                  elif ($rm | test("opus")) then "opus"
                  elif ($rm | test("sonnet")) then "sonnet"
                  elif ($rm | test("haiku")) then "haiku"
                  elif ($rm | test("fable")) then "fable"
                  else null end),
          effort: "inline",
          msg_id: ($m.message.id // null),
          session_id: (if $sid == "" then null else $sid end),
          plugin_version: (if $ver == "" then null else $ver end),
          phase: "inline", risk: null, files: null, tests: null, retry: null, escalated_from: null,
          resolved_model: $rm,
          tokens: (if $u == null then 0
                   else $u.input_tokens + $u.output_tokens
                        + ($u.cache_creation_input_tokens // 0)
                        + ($u.cache_read_input_tokens // 0) end),
          reason: $reason,
          duration_ms: 0
        }
    else empty end
' "$transcript") || fail "log-inline: jq failed on transcript"
if [ -n "$line" ]; then
  # ponytail: only the last 50 rows are checked for a duplicate msg_id; enough for back-to-back Stops.
  mid=$(printf '%s' "$line" | jq -r '.msg_id // empty')
  [ -n "$mid" ] && [ -f "$log" ] && tail -n 50 "$log" | grep -qF "\"msg_id\":\"$mid\"" && exit 0
  mkdir -p "$(dirname "$log")"
  printf '%s\n' "$line" >> "$log"
fi
exit 0
