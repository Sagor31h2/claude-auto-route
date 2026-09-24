#!/usr/bin/env bash
f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
[ -s "$f" ] && command -v jq >/dev/null && jq -rs 'group_by("\(.model) + \(.effort)") | map("\(.[0].model) + \(.[0].effort)\t\(length) runs\t\(map(.tokens // 0) | add) tokens\t\((map(.duration_ms // 0) | add) / length / 1000 | round)s avg") | .[]' "$f" || echo "No routed calls logged yet."
