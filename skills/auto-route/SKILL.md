---
name: auto-route
description: Pick model and reasoning effort per task and delegate to a matching subagent; also toggles always-on routing. Use for /auto-route:auto-route [on|off|status|stats|<task>] or when asked to auto-route or pick the model.
---

## Commands

Argument: `$ARGUMENTS`. Trim it and match case-insensitively. Only the user toggles; never do it on your own. Anything else is a task (see Route).

- `on`: `touch "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on"`
- `off`: `rm -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on"`
- `status`: change nothing.
- `stats`: run `bash <this skill's base directory>/stats.sh` and show the result as a compact table (route, runs, tokens, average seconds).

After `on`, `off` or `status`, run `[ -f "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/auto-route.on" ] && echo ON || echo OFF` and reply with one line: `Auto-route: ON` or `Auto-route: OFF`.

## Route

Route the argument, or the current user prompt if there is none.

**Don't delegate** a pure chat question that needs no tools, or a tiny task that depends on context already in this conversation (re-explaining costs more than doing). Answer those inline.

### Phases

Pick the phase first; the rubric fills in anything it leaves open.

| Phase | When | Route |
|---|---|---|
| Plan | Multi-step, 3+ files, or unclear approach | `opus` + `effort-high` (`effort-xhigh` for architecture or migrations), read-only |
| Research | Find code, explain behavior, gather facts | `haiku`/`sonnet` + `effort-low`/`effort-medium`, read-only, file:line findings |
| Implement | A concrete change | Rubric; one plan step per delegation |
| Debug | Unknown cause, flaky or intermittent failure | `sonnet`/`opus` + `effort-high`/`effort-xhigh`; root cause before fix |
| Review | After a risky or multi-file change | `sonnet` + `effort-high`, read-only, problems only |

The planner returns 3-5 coarse steps, each with What, Files, Depends on, Done when, and Route (model + effort). In Claude Code plan mode, stop after the plan and wait for approval. Otherwise show the plan in a few lines, then route each step with its suggested route (fix it if clearly wrong). Run steps in parallel only when they're independent and touch disjoint files. After the last step of a risky or multi-file plan, run a Review.

### Rubric

Score two independent axes, then call the Agent tool with `subagent_type` = the effort agent and `model` = the chosen model (always pass `model`).

Model = capability or knowledge needed:
- `haiku`: mechanical, well-specified, small (rename, format, lookup, run a command)
- `sonnet`: normal engineering (features, known-location bugs, tests, explanations)
- `opus`: broad scope or hard judgment (architecture, many files, security, unfamiliar domain)
- Never `fable`: pricier than Opus, and it ignores per-turn effort.

Effort = step-by-step reasoning needed:
- `auto-route:effort-low`: obvious once the code is seen
- `auto-route:effort-medium`: a few steps
- `auto-route:effort-high`: tracing logic, unknown cause, tricky edge cases
- `auto-route:effort-xhigh`: concurrency, subtle correctness, proofs, long debugging
- `auto-route:effort-max`: only the single retry after `opus` + `effort-xhigh` fell short; `opus` only

Examples: typo = `haiku` + `effort-low`; find a definition = `haiku` + `effort-low`; mechanical rename across many files = `sonnet` + `effort-low`; small but subtle race condition = `sonnet` + `effort-xhigh`. Unsure on an axis: take the higher value on that axis only.

### Handoff

Subagents start with no memory of this conversation. Every delegation prompt contains:

```
Goal: <one sentence>
Context: <file paths, relevant snippets, decisions made, what was ruled out, results of earlier plan steps>
Constraints: <what not to touch, style rules>
Done when: <the concrete check or deliverable>
```

For Plan, Research and Review, start the prompt with: Read-only: do not modify files.

### Rules

- Before delegating, say the route in one line: `Route: <model> + <effort> (<reason>)`, e.g. `Route: sonnet + high (unknown-cause bug in known file)`.
- Route independent parts separately, in parallel.
- After the agent returns, relay the result briefly.
- Retry at most once, and only for capability failures (wrong or incomplete result, the agent gave up or was unsure). Raise the axis that fell short: reasoning -> next effort (up to `effort-xhigh`; `effort-max` only from `opus` + `effort-xhigh`); capability or knowledge -> next model (up to `opus`). No higher step, or the retry also falls short: report to the user. Never retry permission denials, missing files, or tool and environment errors; report the blocker.
