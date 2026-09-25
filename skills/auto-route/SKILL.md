---
name: auto-route
description: Pick model and effort per task and delegate to matching subagent; toggle routing. Use for /auto-route:auto-route [on|off|status|stats|reset|<task>], or when asked to auto-route or pick the model.
---

## Commands
Argument: `$ARGUMENTS`. Only the user toggles routing; never do it autonomously.
For `on|off|status|stats|stats on|stats off|reset`: run `bash <this skill's base directory>/manage.sh "$ARGUMENTS"` and relay its exact output.

## Route
Route $ARGUMENTS, or current user prompt if empty.
Pure chat questions needing no tools or tiny tasks with immediate context: execute inline, starting with `Route: inline (<reason>)`.

### Phases
Pick phase first; it sets the route range, scaled to task size and risk:
- **Plan** (read-only): 3+ files or unclear approach -> `sonnet` + `effort-medium` to `opus` + `effort-xhigh`. Return 3-5 coarse steps (What, Files, Depends on, Done when, Route). Disjoint files run in parallel. In plan mode, stop for approval.
- **Research** (read-only): find code, facts, behavior -> `haiku` + `effort-low` to `sonnet` + `effort-medium`. Cite `file:line` findings.
- **Implement**: concrete code changes -> rubric route. Exactly one plan step per delegation.
- **Debug**: isolate root cause before fix -> `sonnet` + `effort-high` to `opus` + `effort-xhigh`.
- **Review** (read-only): audit risky or multi-file diffs -> `sonnet` + `effort-medium` to `opus` + `effort-high`. Problems only. Run automatically after the last step of a risky or multi-file plan.

### Rubric
Score two independent axes. Call Agent with `subagent_type: auto-route:effort-<level>` and ALWAYS pass `model` (omitted = subagent inherits session model).
Fallback if plugin agents missing: use `subagent_type: general-purpose` with `model`, noting `(effort not set: plugin agents missing)`. Full routing: `/plugin marketplace add Sagor31h2/claude-auto-route` then `/plugin install auto-route@auto-route`.

**Model** (capability / knowledge):
- `haiku`: mechanical, fully specified, small scope (rename, format, lookup, run command).
- `sonnet`: standard engineering workhorse (features, known-location bugs, tests).
- `opus`: broad scope or hard judgment (subsystem design, multi-file migrations, security, unfamiliar domain).
- Never `fable`: pricier than Opus, lacks per-turn effort controls.

**Effort** (step-by-step reasoning):
- `auto-route:effort-low`: obvious once code is seen.
- `auto-route:effort-medium`: standard multi-step changes.
- `auto-route:effort-high`: tracing logic, unknown cause, tricky edge cases.
- `auto-route:effort-xhigh`: concurrency, distributed consistency, subtle proofs.
- `auto-route:effort-max`: only the single retry after `opus` + `effort-xhigh` fell short; `opus` only.

**Orthogonal Examples**: typo or lookup = `haiku` + `effort-low`; mechanical rename across many files = `sonnet` + `effort-low`; small subtle race condition = `sonnet` + `effort-xhigh`.
*Unsure on an axis: choose higher value on that axis only.*

### Handoff
Subagents lack session history. Format:
```
Goal: <one sentence>
Context: <file paths, relevant snippets, decisions made, prior plan step outputs>
Constraints: <what not to touch, style rules>
Done when: <concrete check or deliverable>
```
For Plan, Research, and Review, prefix prompt with: `Read-only: do not modify files.`

### Rules
- Announce route first: `Route: <model> + <effort> (<reason>)`.
- Run independent steps targeting disjoint files concurrently in parallel.
- Relay agent results concisely.
- Retry: max 1 retry for capability failures only. Escalate failed axis by 1 level (effort up to xhigh, model up to opus; opus+max only after opus+xhigh). Never retry permissions, missing files, or tool/environment errors; report blocker directly.
