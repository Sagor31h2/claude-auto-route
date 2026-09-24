---
name: auto-route
description: Auto-pick model and reasoning effort for a task, independently, by delegating to an effort-level subagent with a per-call model. Also toggles always-on routing. Use when the user says "auto-route", "auto model", "pick the model", or invokes /auto-route:auto-route [on|off|status|<task>].
---

## Toggle

Argument: `$ARGUMENTS`

If the argument is exactly `on`, `off`, or `status`, handle it here and stop. Only do this when the user typed it; never toggle on your own.

- `on`: run `touch ~/.claude/auto-route.on`
- `off`: run `rm -f ~/.claude/auto-route.on`
- `status`: change nothing

Then run `[ -f ~/.claude/auto-route.on ] && echo ON || echo OFF` and reply with one line: `Auto-route: ON` or `Auto-route: OFF`.

While the flag file exists, this plugin's UserPromptSubmit hook asks Claude to route every prompt through this skill.

## Route

Otherwise, route the task (the argument, or the current user prompt if there is no argument).

Score the task on two separate axes, then delegate with the Agent tool: `subagent_type` = the effort agent, `model` = the chosen model. Always pass `model`. Pass the full task and all context; the agent starts fresh.

**Model = how much capability/knowledge the task needs**
- `haiku`: mechanical, well-specified, small scope (rename, format, lookup, run a command)
- `sonnet`: normal engineering work (features, known-location bugs, tests, explanations)
- `opus`: broad scope or hard judgment (architecture, many files, security, unfamiliar domain)

**Effort = how much step-by-step reasoning the task needs**
- `auto-route:effort-low`: answer is obvious once the code is seen
- `auto-route:effort-medium`: a few steps of reasoning
- `auto-route:effort-high`: tracing logic, unknown cause, tricky edge cases
- `auto-route:effort-xhigh`: concurrency, subtle correctness, proofs, long multi-step debugging

The axes are independent. Examples: large but mechanical migration = `opus` + `effort-low`; small but subtle race condition = `sonnet` + `effort-xhigh`; typo = `haiku` + `effort-low`.

Rules:
- Unsure on an axis: pick the higher value on that axis only.
- Pure chat question answerable without tools: answer inline, no delegation.
- Independent parts of different difficulty: route each separately, in parallel.
- Before delegating, tell the user in one line, e.g. `Route: sonnet + high (unknown-cause bug in known file)`.
- After the agent returns, relay the result briefly. If it failed or was unsure, retry once raising whichever axis caused the failure.
