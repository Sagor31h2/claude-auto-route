#!/usr/bin/env bash
# Usage: stats.sh [since YYYY-MM-DD]   (only rows/errors with ts on or after that date; ts are UTC)
dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
f="$dir/auto-route.log"
errf="$dir/auto-route.err"
since=""
if [ "${1:-}" = since ]; then
  [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Usage: stats.sh [since YYYY-MM-DD]"; exit 1; }
  since=$2
fi
out=""
if [ -s "$f" ] && command -v jq >/dev/null; then
# Inline rows log whole-session context size, not cost, so they stay out of the token totals.
# Rows from before Route-meta lack phase/retry; those are skipped in the escalation/phase/meta lines.
out=$(jq -n -R -r --arg since "$since" '
  def med: sort | if length == 0 then 0 else (.[(length - 1) / 2 | floor] + .[length / 2 | floor]) / 2 end;
  def p90: sort | .[((length * 0.9 | ceil) - 1)];
  # ponytail: list prices per MTok [input, output, cache read] from the README table; they go stale, update there too.
  # rates_exact is matched on the row resolved_model prefix first (add a pricier/cheaper model version here),
  # then rates by family alias. Cache writes are priced at 1.25x the input rate.
  def rates: {haiku: [1, 5, 0.1], sonnet: [2, 10, 0.2], opus: [4, 20, 0.2], fable: [10, 50, 0.25]};
  def rates_exact: {"claude-haiku-4-5": [1, 5, 0.1], "claude-sonnet-5": [2, 10, 0.2], "claude-opus-5-5": [4, 20, 0.2], "claude-fable-5-1": [10, 50, 0.25]};
  def rate: (.resolved_model // "") as $rm
    | ([rates_exact | to_entries[] | . as $e | select($rm | startswith($e.key))] | sort_by(.key | length) | last | .value)
      // rates[.model // ""];
  # priced = row has everything needed for a full estimate (rows lacking cache_read_tokens are not guessed at 0)
  def priced: rate != null and .out_tokens != null and .new_tokens != null and .cache_read_tokens != null;
  def cost: rate as $r | (.cache_creation_tokens // 0) as $w
    | ((.new_tokens - $w) * $r[0] + $w * $r[0] * 1.25 + .out_tokens * $r[1] + .cache_read_tokens * $r[2]) / 1000000;
  def r3: . * 1000 | round / 1000;
  def slow_ms: 600000; # delegated runs longer than this count as slow
  def run_cap: 2;      # routes averaging more than this many dollars per run are flagged
  def s: (. / 1000 | round | tostring) + "s";
  def secs: try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch 0;
  def tier: [({haiku: 0, sonnet: 1, opus: 2, fable: 3}[.model // ""] // 0), ({low: 0, medium: 1, high: 2, xhigh: 3, max: 4}[.effort // ""] // 0)];
  def higher($a; $b): $a != $b and $a[0] >= $b[0] and $a[1] >= $b[1];
  # a repeated SubagentStop appends another row for the same agent_id: keep only the last (group_by is stable);
  # rows without an agent_id are all kept. Dedupe before the since filter so the latest row decides.
  [inputs | fromjson? | select(type == "object")] as $rows
  | ($rows | map(select((.agent_id // "") == "")) + ($rows | map(select((.agent_id // "") != "")) | group_by(.agent_id) | map(last))
     | map(select($since == "" or ((.ts // "" | tostring) >= $since)))) as $all
  | if ($all | length) == 0 then empty else
    ($all | map(select(.effort != "inline"))) as $d
    | ($all | map(select(.effort == "inline"))) as $i
    | ($d | group_by("\(.model) + \(.effort)") | map(
        "\(.[0].model) + \(.[0].effort)\t\(length) runs\t\(map(.tokens // 0) | add) tokens\tmedian \(map(.duration_ms // 0) | med | s) p90 \(map(.duration_ms // 0) | p90 | s)"
        # out = output tokens; ~$ = approx cost over the priced runs: new_tokens (less cache creation) at the input rate,
        # cache creation at 1.25x input, out_tokens at the output rate, cache_read_tokens at the cache-read rate.
        # "N of M runs priced" shows how many runs the estimate covers; the rest lack token fields.
        + (map(select(.out_tokens != null)) as $o | if ($o | length) > 0 then "\tout \($o | map(.out_tokens) | add)" else "" end)
        + (length as $n | map(select(rate != null)) as $rt | map(select(priced)) as $c
           | if ($rt | length) == 0 then ""
             elif ($c | length) == 0 then "\t0 of \($n) runs priced"
             else ($c | map(cost) | add) as $t | ($t / ($c | length)) as $pr
               | "\t~$\($t | r3) (approx\(if ($c | any(.cache_creation_tokens == null)) then ", old rows lack cache write split" else "" end))\t$\($pr | r3)/run\(if $pr > run_cap then " OVER $\(run_cap)/run" else "" end)\t\($c | length) of \($n) runs priced"
             end))
      | .[]),
      (if ($i | length) > 0 then "inline\t\($i | length) turns\tmedian \($i | map(.tokens // 0) | med | round) tokens (context size, not cost)"
          # relay/ack/done reasons are one bucket; rows without a reason are counted separately
          + ($i | map(.reason // empty | if test("\\b(relay(ing)?|ack(nowledg\\w*)?|done)\\b"; "i") then "relay/ack" else . end)
             | group_by(.) | map({r: .[0], n: length}) | sort_by(-.n) | .[:3]
             | if length > 0 then "; top reasons: " + (map("\(.r) (\(.n))") | join(", ")) else "" end)
          + ($i | map(select(.reason == null)) | length | if . > 0 then "; no reason: \(.)" else "" end)
        else empty end),
      # per-field meta: phase != null marks a row with usable meta, retry != null only the escalation line
      ($d | map(select(.phase != null))) as $p
      | ($d | map(select(.retry != null))) as $m
      | (if ($m | length) > 0 then "escalation: \($m | map(select(.retry == true)) | length)/\($m | length) delegated runs with retry (\(($m | map(select(.retry == true)) | length) * 100 / ($m | length) | round)%)" else empty end),
      # inferred retry: the same goal_hash and phase delegated again within 30 min at a higher tier, whatever the row declared
      ($d | map(select(.goal_hash != null and .ts != null)) | sort_by(.ts)) as $g
      | (if ($g | length) > 0 then
          "inferred retry: \($g | to_entries | map(.key as $k | .value as $v
            | select($g[:$k] | any(.goal_hash == $v.goal_hash and .phase == $v.phase and (($v.ts | secs) - (.ts | secs)) <= 1800
                                   and higher($v | tier; . | tier)))) | length) (same goal re-delegated at a higher tier within 30min)"
        else empty end),
      ($p | group_by(.phase) | .[] | "\(.[0].phase): " + (group_by("\(.model)+\(.effort)") | map("\(.[0].model)+\(.[0].effort) \(length)") | join(", "))),
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
      # untested multi-file work (tests n, 3+ files) is a legitimate reason for high effort on low risk, so it is not a mismatch
      ($d | map(select(.risk == "high" and (.effort | IN("low","medium")))) | length) as $hl
      | ($d | map(select(.risk == "low" and (.effort | IN("high","xhigh")) and ((.tests == "n" and (.files // 0) >= 3) | not))) | length) as $lh
      | (if $hl + $lh > 0 then "mismatch: high-risk on low/medium effort \($hl), low-risk on high/xhigh effort \($lh)" else empty end),
      (if ($p | length) > 0 then "meta: \($p | length)/\($d | length) delegated runs carry Route-meta" else empty end)
  end' "$f" 2>/dev/null)
fi
[ -n "$out" ] && { [ -n "$since" ] && echo "(since $since)"; echo "$out"; } || echo "No routed calls logged yet."
if [ -s "$errf" ]; then
  n=$(awk -v s="$since" '$1 >= s' "$errf" | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && echo "hook errors: $n logged in $errf"
fi
exit 0
