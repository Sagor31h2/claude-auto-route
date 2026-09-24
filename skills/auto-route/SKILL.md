---
name: auto-route
description: Pick model and reasoning effort per task and delegate to a matching subagent; also toggles always-on routing. Use for /auto-route:auto-route [on|off|status|stats|<task>] or when asked to auto-route or pick the model.
---

## Commands

Argument: `$ARGUMENTS`

Trim the argument and match case-insensitively (`on`, `off`, `status`, or `stats`). If it matches, handle it here and stop; anything else is treated as a task. Only do this when the user typed it; never toggle on your own.

- `on`: run `touch "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on"`
- `off`: run `rm -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on"`
- `status`: change nothing
- `stats`: run the snippet below and reply with a compact table (route, runs, tokens, average seconds), or the no-calls message:
```bash
f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.log"
[ -s "$f" ] && jq -rs 'group_by("\(.model) + \(.effort)") | map("\(.[0].model) + \(.[0].effort)\t\(length) runs\t\(map(.tokens // 0) | add) tokens\t\((map(.duration_ms // 0) | add) / length / 1000 | round)s avg") | .[]' "$f" || echo "No routed calls logged yet."
```

For `on`, `off`, and `status`: run `[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on" ] && echo ON || echo OFF` and reply with one line: `Auto-route: ON` or `Auto-route: OFF`.

While the flag file exists, this plugin's UserPromptSubmit hook asks Claude to route every prompt through this skill. A PostToolUse hook logs each routed call (time, model, effort, resolved model, tokens, duration; no prompt or task text) to auto-route.log in the same directory.

## Route

Otherwise, route the task (the argument, or the current user prompt if there is no argument).

### When not to delegate

Answer inline when:
- It is a pure chat question needing no tools.
- The task is tiny and depends on context already in this conversation, so re-explaining it to a fresh agent costs more than doing it.

### Phases

Pick the phase first, then use the Rubric for anything the phase leaves open.

| Phase | When | Default route | Notes |
|---|---|---|---|
| Plan | Multi-step task, 3+ files, or unclear approach | `opus` + `effort-high` (`effort-xhigh` for architecture or migrations) | Read-only. Returns the plan format below. |
| Research | Find code, explain behavior, gather facts | `haiku` or `sonnet` + `effort-low`/`effort-medium` | Read-only. Findings with file:line. |
| Implement | A concrete change | Rubric | One plan step per delegation. |
| Debug | Unknown cause, flaky or intermittent failure | `sonnet` or `opus` + `effort-high`/`effort-xhigh` | Find the root cause before fixing. |
| Review | After a risky or multi-file change | `sonnet` + `effort-high` | Read-only. Report problems only. |

Plan format the planner must return: 3-5 coarse steps; each step lists What, Files, Depends on, Done when, and Route (model + effort).

Executing a plan:
- If the session is in Claude Code plan mode, stop after the plan and present it for approval. Execute only after approval.
- Otherwise show the plan in a few lines, then route each step using its suggested route (adjust if it's clearly wrong).
- Carry results forward: put what earlier steps changed (files, new interfaces, key decisions) into the next step's handoff Context, because each subagent starts blank.
- Run steps in parallel only when they don't depend on each other and touch disjoint files; otherwise run them in order.
- After the last step of a risky or multi-file plan, run a Review.

### Rubric

Score the task on two separate axes, then delegate with the Agent tool: `subagent_type` = the effort agent, `model` = the chosen model. Always pass `model`. Pass the full task and all context; the agent starts fresh.

**Model = how much capability/knowledge the task needs**
- `haiku`: mechanical, well-specified, small scope (rename, format, lookup, run a command)
- `sonnet`: normal engineering work (features, known-location bugs, tests, explanations)
- `opus`: broad scope or hard judgment (architecture, many files, security, unfamiliar domain)
- Never route to `fable`: it costs about 2.5x Opus, Opus matches or beats it on most tasks, and it doesn't accept per-turn effort, which the effort agents rely on.

**Effort = how much step-by-step reasoning the task needs**
- `auto-route:effort-low`: answer is obvious once the code is seen
- `auto-route:effort-medium`: a few steps of reasoning
- `auto-route:effort-high`: tracing logic, unknown cause, tricky edge cases
- `auto-route:effort-xhigh`: concurrency, subtle correctness, proofs, long multi-step debugging
- `auto-route:effort-max`: never a first pick. Only for the single retry after `opus` + `effort-xhigh` fell short, and only with `opus`.

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

For read-only phases (Plan, Research, Review), start the prompt with: Read-only: do not modify files.

### Rules

- Unsure on an axis: pick the higher value on that axis only.
- Pure chat question answerable without tools: answer inline, no delegation.
- Independent parts of different difficulty: route each separately, in parallel.
- Before delegating, tell the user in one line, e.g. `Route: sonnet + high (unknown-cause bug in known file)`.
- After the agent returns, relay the result briefly.
- Retry at most once, and only for capability failures (wrong or incomplete result, the agent gave up or was unsure). Raise the axis that fell short: reasoning fell short -> next effort level (up to `effort-xhigh`; `effort-max` only from `opus` + `effort-xhigh`); capability or knowledge fell short -> next model (up to `opus`). If there is no higher step or the retry also falls short, report to the user. Never retry permission denials, missing files, or tool and environment errors; report the blocker instead.
