#!/usr/bin/env bash
f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
[ -s "$f" ] && command -v jq >/dev/null || { echo "No routed calls logged yet."; exit 0; }
# Inline rows log whole-session context size, not cost, so they stay out of the token totals.
# Rows from before Route-meta lack phase/retry; those are skipped in the escalation/phase/meta lines.
out=$(jq -n -R -r '
  def med: sort | if length == 0 then 0 else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
  def p90: sort | .[((length * 0.9 | ceil) - 1)];
  # ponytail: list prices per MTok [input, output, cache read] from the README table; they go stale, update there too.
  def rates: {haiku: [1, 5, 0.1], sonnet: [2, 10, 0.2], opus: [4, 20, 0.2], fable: [10, 50, 0.25]};
  def slow_ms: 600000; # delegated runs longer than this count as slow
  def s: (. / 1000 | round | tostring) + "s";
  [inputs | fromjson? | select(. != null)] as $all
  | if ($all | length) == 0 then empty else
    ($all | map(select(.effort != "inline"))) as $d
    | ($all | map(select(.effort == "inline"))) as $i
    | ($d | group_by("\(.model) + \(.effort)") | map(
        "\(.[0].model) + \(.[0].effort)\t\(length) runs\t\(map(.tokens // 0) | add) tokens\tmedian \(map(.duration_ms // 0) | med | s) p90 \(map(.duration_ms // 0) | p90 | s)"
        # out = output tokens; ~$ = approx cost: new_tokens at input rate (cache creation too) + out_tokens at output rate
        # + cache_read_tokens at cache-read rate; older rows lack cache_read_tokens (counted as 0) and flag the estimate
        + (map(select(.out_tokens != null)) as $o | if ($o | length) > 0 then "\tout \($o | map(.out_tokens) | add)" else "" end)
        + (.[0].model as $mo | (rates[$mo // ""]) as $r
           | map(select(.out_tokens != null and .new_tokens != null)) as $c
           | if $r != null and ($c | length) > 0
             then "\t~$\($c | map((.new_tokens * $r[0] + .out_tokens * $r[1] + (.cache_read_tokens // 0) * $r[2]) / 1000000) | add * 1000 | round / 1000) (approx\(if ($c | any(.cache_read_tokens == null)) then ", old rows lack cache reads" else "" end))"
             else "" end))
      | .[]),
      (if ($i | length) > 0 then "inline\t\($i | length) turns\tmedian \($i | map(.tokens // 0) | med | round) tokens (context size, not cost)"
          + ($i | map(.reason // empty) | group_by(.) | map({r: .[0], n: length}) | sort_by(-.n) | .[:3]
             | if length > 0 then "; top reasons: " + (map("\(.r) (\(.n))") | join(", ")) else "" end)
        else empty end),
      ($d | map(select(.retry != null))) as $m
      | (if ($m | length) > 0 then "escalation: \($m | map(select(.retry == true)) | length)/\($m | length) delegated runs with retry (\(($m | map(select(.retry == true)) | length) * 100 / ($m | length) | round)%)" else empty end),
      ($m | group_by(.phase) | .[] | "\(.[0].phase): " + (group_by("\(.model)+\(.effort)") | map("\(.[0].model)+\(.[0].effort) \(length)") | join(", "))),
      ($d | group_by("\(.model)+\(.effort)") | map(
         "\(.[0].model)+\(.[0].effort)" as $k | length as $n
         | ($m | map(select(.retry == true and .escalated_from == $k)) | length) as $e
         | select($e > 0) | "\($k) \($e)/\($n) (\($e * 100 / $n | round)%)")
       | if length > 0 then "escalated away: " + join(", ") else empty end),
      ($d | group_by("\(.model)+\(.effort)") | map(
         "\(.[0].model)+\(.[0].effort)" as $k | length as $n
         | (map(select((.duration_ms // 0) > slow_ms)) | length) as $e
         | select($e > 0) | "\($k) \($e)/\($n) (\($e * 100 / $n | round)%)")
       | if length > 0 then "slow (>\(slow_ms / 60000 | round)min): " + join(", ") else empty end),
      ($m | map(select(.risk == "high" and (.effort | IN("low","medium")))) | length) as $hl
      | ($m | map(select(.risk == "low" and (.effort | IN("high","xhigh")))) | length) as $lh
      | (if $hl + $lh > 0 then "mismatch: high-risk on low/medium effort \($hl), low-risk on high/xhigh effort \($lh)" else empty end),
      (if ($m | length) > 0 then "meta: \($m | length)/\($d | length) delegated runs carry Route-meta" else empty end)
  end' "$f" 2>/dev/null)
[ -n "$out" ] && echo "$out" || echo "No routed calls logged yet."
