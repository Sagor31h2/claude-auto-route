---
name: auto-route
description: Pick model and reasoning effort per task and delegate to a matching subagent; also toggles always-on routing. Use for /auto-route:auto-route [on|off|status|<task>] or when asked to auto-route or pick the model.
---

## Toggle

Argument: `$ARGUMENTS`

Trim the argument and match case-insensitively (`on`, `off`, `status`). If it matches, handle it here and stop; anything else is treated as a task. Only do this when the user typed it; never toggle on your own.

- `on`: run `touch "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on"`
- `off`: run `rm -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on"`
- `status`: change nothing

Then run `[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on" ] && echo ON || echo OFF` and reply with one line: `Auto-route: ON` or `Auto-route: OFF`.

While the flag file exists, this plugin's UserPromptSubmit hook asks Claude to route every prompt through this skill.

## Route

Otherwise, route the task (the argument, or the current user prompt if there is no argument).

### When not to delegate

Answer inline when:
- It is a pure chat question needing no tools.
- The task is tiny and depends on context already in this conversation, so re-explaining it to a fresh agent costs more than doing it.

### Rubric

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

The axes are independent. Examples: large but mechanical rename across many files = `sonnet` + `effort-low`; find where a function is defined = `haiku` + `effort-low`; small but subtle race condition = `sonnet` + `effort-xhigh`; typo = `haiku` + `effort-low`.

### Handoff

The subagent starts with no memory of this conversation, so every delegation prompt must contain:
- Goal (one sentence)
- Context already known (file paths, relevant snippets, decisions made, what was ruled out)
- Constraints (what not to touch, style rules)
- Done when (the concrete check or deliverable)

```
Goal: <one sentence>
Context: <file paths, relevant snippets, decisions made, what was ruled out>
Constraints: <what not to touch, style rules>
Done when: <the concrete check or deliverable>
```

### Rules

- Unsure on an axis: pick the higher value on that axis only.
- Pure chat question answerable without tools: answer inline, no delegation.
- Independent parts of different difficulty: route each separately, in parallel.
- Before delegating, tell the user in one line, e.g. `Route: sonnet + high (unknown-cause bug in known file)`.
- After the agent returns, relay the result briefly. If it failed or was unsure, retry once raising whichever axis caused the failure.
