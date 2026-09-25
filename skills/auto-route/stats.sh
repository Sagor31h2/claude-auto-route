#!/usr/bin/env bash
f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
[ -s "$f" ] && command -v jq >/dev/null || { echo "No routed calls logged yet."; exit 0; }
out=$(jq -n -R -r '[inputs | fromjson? | select(. != null)] | if length == 0 then empty else group_by("\(.model) + \(.effort)") | map("\(.[0].model) + \(.[0].effort)\t\(length) runs\t\(map(.tokens // 0) | add) tokens\t\((map(.duration_ms // 0) | add) / length / 1000 | round)s avg") | .[] end' "$f" 2>/dev/null)
[ -n "$out" ] && echo "$out" || echo "No routed calls logged yet."
