#!/usr/bin/env bash
# UserPromptSubmit: when always-on is enabled, ask Claude to route the prompt via the auto-route skill.
[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on" ] || exit 0
input=$(cat)
# Skip slash commands and short acknowledgements/cancellations; fail open (route) if jq is missing or parsing fails.
if command -v jq >/dev/null 2>&1; then
  skip=$(printf '%s' "$input" | jq -r '(.prompt // "") as $p
    | ($p | test("\\A/[A-Za-z0-9_:-]+(\\s|\\z)"))
      or ($p | test("\\A\\s*((ok(ay)?|y(es)?|yep|yeah|sure|no(pe)?|nah|wait|hold on)[,.!?]?\\s*)?(continue|go( on| ahead)?|proceed|do it|next|done|lgtm|looks good|thanks?( you)?|ty|nice|great|good|perfect|stop|cancel|nevermind|never mind|don'\''?t( do that)?)?\\s*[.!?]*\\s*\\z"; "i"))' 2>/dev/null)
  [ "$skip" = "true" ] && exit 0
fi
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"AUTO-ROUTE ON: handle this prompt via the auto-route:auto-route skill. Pure chat questions may be answered inline."}}'
