---
name: auto-route
description: Pick model and effort per task and delegate to matching subagent; toggle routing. Use for /auto-route:auto-route [on|off|status|stats|reset|<task>], or when asked to auto-route or pick the model.
---

## Commands
Argument: `$ARGUMENTS`. Only the user toggles routing; never do it autonomously.
For `on|off|status|stats|stats on|stats off|reset`: run `bash <this skill's base directory>/manage.sh "$ARGUMENTS"` and relay its exact output.

## Route
Route $ARGUMENTS, or current user prompt if empty.
Score from the request and what you already know; never explore the repo just to route (subagents explore). Unknown signal = cheaper tier, escalate on failure.
Pure chat questions needing no tools or tiny tasks with immediate context: execute inline, starting with `Route: inline (<reason>)`.

### Phases
Pick phase first; it sets behavior only, never a model/effort range. Any phase may route `haiku`..`opus`, `low`..`xhigh` per the Rubric:
- **Plan** (read-only): 3+ files with high risk (auth, migrations, concurrency), or an approach unclear across modules. Plan first, before any Implement. Return 3-5 coarse steps (What, Files, Depends on, Done when, Route). Disjoint files run in parallel. In plan mode, stop for approval.
- **Research** (read-only): find code, facts, behavior. Cite `file:line` findings.
- **Implement**: concrete code changes. Exactly one plan step per delegation.
- **Debug**: isolate root cause before fix.
- **Review** (read-only): audit risky or multi-file diffs. Problems only. Run automatically after the last step of a risky or multi-file plan.

### Rubric
Score signals, not task type, on two independent axes. Call Agent with `subagent_type: auto-route:effort-<level>` and ALWAYS pass `model` (omitted = subagent inherits session model).
Fallback if plugin agents missing: use `subagent_type: general-purpose` with `model`, noting `(effort not set: plugin agents missing)`. Full routing: `/plugin marketplace add Sagor31h2/claude-auto-route` then `/plugin install auto-route@auto-route`.

**Model** (capability) = risk surface (auth, crypto, concurrency, migrations), domain novelty, tests present?, prior failure:
- `haiku`: mechanical, fully specified, small scope (rename, format, lookup, run command).
- `sonnet`: standard engineering workhorse (features, known-location bugs, tests).
- `opus`: broad scope or hard judgment (subsystem design, multi-file migrations, security, unfamiliar domain).
- Never `fable`: pricier than Opus, lacks per-turn effort controls.

**Effort** (reasoning depth) = diff size, file count, fan-out, trace depth:
- `auto-route:effort-low`: obvious once code is seen.
- `auto-route:effort-medium`: standard multi-step changes.
- `auto-route:effort-high`: tracing logic, unknown cause, tricky edge cases.
- `auto-route:effort-xhigh`: deep concurrency/consistency traces, subtle proofs.
- `auto-route:effort-max`: only the single retry after `opus` + `effort-xhigh` fell short; `opus` only.

**Default = cheap-first cascade**: pick the lowest viable tier; on capability failure escalate only the failed axis (see Retry). A trivial/small change with no tests stays cheap-first. Start high only by axis:
- concurrency: `opus` + `effort-xhigh`.
- security/auth: `opus` + `effort-high` (xhigh only for subtle crypto/proofs).
- irreversible migration: `opus` + `effort-high`.
- no tests AND non-trivial (3+ files, even if you already chose the approach, or unclear approach): raise effort first (`effort-high`); model stays `sonnet` unless another risk signal applies.
- Debug, unknown cause: start at `effort-high` (model per Rubric); known-location bugs follow cheap-first.
**Orthogonal Examples**: typo or lookup = `haiku` + `effort-low`; mechanical rename across many files = `sonnet` + `effort-low`; small subtle race condition = `opus` + `effort-xhigh`; 3+ file feature with no tests = `sonnet` + `effort-high`.
*Unsure on an axis: tie-break to the cheaper tier and rely on escalate-on-fail.*

### Split (only when it saves tokens)
Splitting costs a fixed handoff overhead per sub-task, so only split when that overhead is paid back by *not* running every part at the same expensive rate. Split only when both hold:
- 3+ independent concerns (disjoint files, or distinct review dimensions/plan steps) exist in the task, AND
- scoring them separately would spread across 2+ effort or model levels (i.e. today's single route would overpay for the easy parts).
Otherwise route as one block — do not split a uniform or small task just because it has multiple files.
When splitting: score and route each part independently per the Rubric, run disjoint parts in parallel (per Rules below), then merge results yourself in one pass — never a second full-effort review of the merged output.

### Explicit override
A task can pin its own effort level instead of the scored one: prefix it with the
level, `low:` / `medium:` / `high:` / `xhigh:` / `max:` (e.g. `high: plan the auth refactor`).
Applies to every phase (Plan, Research, Implement, Debug, Review) and to any named skill that
takes its own level/effort argument (e.g. `code-review`, which accepts low/medium/high/xhigh/max)
- pass the pinned level straight through as that skill's argument instead of guessing one. Model
still scores normally unless also pinned, `<model>+<level>:` (e.g. `opus+xhigh: ...`). An explicit
user-given level always wins over the scored level or a skill's own default/last-used level.

### Handoff
Subagents lack session history. Format:
```
Route-meta: phase=<plan|research|implement|debug|review> risk=<low|med|high> files=<n> tests=<y|n> retry=<0|1> escalated_from=<model+effort|none>
Goal: <one sentence>
Context: <file paths, relevant snippets, decisions made, prior plan step outputs>
Constraints: <what not to touch, style rules>
Done when: <concrete check or deliverable>
```
`Route-meta` must be the first line (logged for routing stats). For Plan, Research, and Review, add `Read-only: do not modify files.` right after it.

### Rules
- Announce route first: `Route: <model> + <effort> (<reason>)`, `<effort>` = bare level (`low|medium|high|xhigh|max`), not the agent name. If the level was pinned by the
  user rather than scored, say so: `Route: <model> + <effort> (explicit user pin)`.
- Run independent steps targeting disjoint files concurrently in parallel.
- Relay agent results concisely.
- Retry: max 1 retry for capability failures only (tests fail, the Done-when check is unmet, or the subagent reports it could not complete), with the failure context in the prompt (`retry=1`, `escalated_from` = prior route). Escalate failed axis by 1 level (effort up to xhigh, model up to opus; opus+max only after opus+xhigh). Never retry permissions, missing files, or tool/environment errors; report blocker directly.
