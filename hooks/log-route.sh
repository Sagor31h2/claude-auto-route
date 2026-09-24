#!/usr/bin/env bash
# PostToolUse(Agent): append one JSON line per auto-route delegation. Never prints, never fails.
exec >/dev/null 2>&1
command -v jq || exit 0
log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
# ponytail: unbounded append (~150 bytes per call); add rotation if logs ever get large
line=$(jq -c 'select((.tool_input.subagent_type // "") | startswith("auto-route:"))
  | {ts: (now | todate),
     model: (.tool_input.model // null),
     effort: (.tool_input.subagent_type | sub("^auto-route:effort-"; "")),
     resolved_model: (.tool_response.resolvedModel? // null),
     tokens: (.tool_response.totalTokens? // null),
     duration_ms: (.tool_response.totalDurationMs? // null)}') || exit 0
[ -n "$line" ] && printf '%s\n' "$line" >> "$log"
exit 0
