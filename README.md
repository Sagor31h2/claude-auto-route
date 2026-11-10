# auto-route

[![Version](https://img.shields.io/badge/version-1.18.0-blue.svg)](.claude-plugin/plugin.json)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview)
[![Tests](https://img.shields.io/badge/tests-passing-brightgreen.svg)](tests/)

**Picks the right Claude model and reasoning effort for each task, so simple work stays cheap.**

`auto-route` is a Claude Code plugin that classifies each task, delegates it to an isolated subagent at the cheapest model (`haiku`, `sonnet`, `opus`) and effort (`low` to `xhigh`, `max` for one retry) that fits, runs independent steps in parallel, and answers pure chat inline.

## Quick start

Inside Claude Code:

```bash
/plugin marketplace add Sagor31h2/claude-auto-route
/plugin install auto-route@auto-route
/auto-route:auto-route on
```

> [!IMPORTANT]
> **Restart Claude Code** after installing to register the effort subagents and hooks.

Every eligible task is then routed automatically, announced before the work runs:

```text
Route: sonnet + low (mechanical rename across many files)
Route: inline (pure chat question)
```

## Everyday commands

| Command | Description |
|---|---|
| `/auto-route:auto-route on` / `off` | Enable / disable always-on routing of every prompt. |
| `/auto-route:auto-route status` | Show whether always-on mode is `ON` or `OFF`. |
| `/auto-route:auto-route <task>` | Route one task manually. |
| `/auto-route:auto-route stats` | Show telemetry (off by default). |
| `/auto-route:auto-route stats since <YYYY-MM-DD>` | Same, for rows logged on or after that UTC date. |
| `/auto-route:auto-route stats on` / `off` | Enable / disable stats logging (the log is kept on `off`). |
| `/auto-route:auto-route reset` | Clear `~/.claude/auto-route.log` and `~/.claude/auto-route.err`. |

Pin an effort level with a prefix: `low:` / `medium:` / `high:` / `xhigh:` / `max:` (e.g. `high: plan the auth refactor`), or pin the model too with `<model>+<level>:` (e.g. `opus+xhigh: ...`). A pin wins over the scored level and works for every phase and for skills that take a level argument (e.g. `code-review`).

<details>
<summary><b>Routing rubric, phases, and Route-meta</b></summary>

Tasks are scored on signals (risk surface, scope, tests present, prior failure), not task type. The default is **cheap-first**: with tests present and low/medium risk, the lowest viable tier is picked.

- **Model**: `haiku` (mechanical, well-specified), `sonnet` (standard engineering), `opus` (high judgment, broad architecture). `fable` is never used.
- **Effort**: `low`, `medium`, `high`, `xhigh` via the plugin agents `auto-route:effort-low|medium|high|xhigh`; `auto-route:effort-max` is the single retry after `opus + xhigh` falls short.
- **Escalation**: at most one retry, on capability failures only (tests fail, done-when unmet, subagent could not complete), stepping up only the failed axis (effort or model). Environment/tool errors are reported, not retried.
- **Split**: a task with 3+ independent concerns that would score across 2+ effort or model levels is split, routed per part, run in parallel where files are disjoint, and merged in one pass. Otherwise it stays one route.

Phases set behavior only, not the route:

| Phase | Read-only | Purpose |
|---|:---:|---|
| Plan | Yes | 3-5 coarse steps with target files, dependencies, route, done-when. |
| Research | Yes | Locate definitions and call paths; report `file:line`. |
| Implement | No | One plan step per delegation. |
| Debug | No | Establish root cause before fixing. |
| Review | Yes | Report critical defects, correctness bugs, security risks only. |

Each delegation prompt starts with a line the stats hook logs:

```text
Route-meta: phase=<plan|research|implement|debug|review> risk=<low|med|high> files=<integer> tests=<y|n> retry=<0|1> escalated_from=<model+effort|none>
```

</details>

<details>
<summary><b>Always-on skip rules</b></summary>

In always-on mode the `UserPromptSubmit` hook skips slash commands, acknowledgements (`ok`, `yes`, `continue`, `lgtm`...), greetings and thanks, and cancellations (`stop`, `cancel`, `wait`...). A greeting followed by a task (`hi, please fix the bug`) is still routed.

</details>

<details>
<summary><b>Stats (optional, local only)</b></summary>

Stats are off by default and stay on your machine. Enable with `/auto-route:auto-route stats on`; hooks then log each delegated run and inline turn to `~/.claude/auto-route.log`. Requires `jq`.

```text
haiku + low      18 runs   24190 tokens   median 4s p90 7s   out 6100   ~$0.04 (approx)   $0.002/run   18 of 18 runs priced
sonnet + medium  24 runs   64280 tokens   median 17s p90 35s   out 15800   ~$0.31 (approx)   $0.013/run   24 of 24 runs priced
inline           31 turns  median 41200 tokens (context size, not cost); top reasons: pure chat question (14), relay/ack (9)
escalation: 4/50 delegated runs with retry (8%)
escalated away: sonnet+low 3/12 (25%)
hook errors: 1 logged in ~/.claude/auto-route.err
```

Each route row shows runs, tokens (final-turn context), median/p90 duration, output tokens, and approximate cost from list prices (rates live in `skills/auto-route/stats.sh`). Inline rows show context size, not cost. `escalation` is the share of delegated runs that were retries, `escalated away` is the per-route share that needed a retry on a higher tier (above roughly 15-20% that tier is taking tasks it shouldn't), and per-phase lines summarize routes used. Other lines: `inferred retry` (same goal re-delegated at a higher tier in the same phase within 30 min, even without `retry=1`), `mismatch` (high-risk on low/medium effort, or low-risk on high/xhigh, ignoring the no-tests, 3+ files rule), `slow (>10min)`, and `meta:` (how many delegated rows carry Route-meta; use `stats since <date>` to skip older rows). Routes over $2/run are flagged `OVER $2/run`, and `N of M runs priced` shows how many rows had enough token data to cost.

Log fields (one JSON line per row):

- Delegated: `ts`, `model`, `effort`, `resolved_model`, `tokens`, `out_tokens`, `new_tokens`, `cache_creation_tokens`, `cache_read_tokens`, `duration_ms`, `agent_id`, `session_id`, `goal_hash`, `plugin_version`, plus the parsed Route-meta fields `phase`, `risk`, `files`, `tests`, `retry`, `escalated_from`. A missing or malformed meta field logs `null` for that field only.
- Inline: `effort: "inline"`, `phase: "inline"`, `reason` (from `Route: inline (<reason>)`, max 80 chars), `msg_id`, `session_id`, `plugin_version`.

</details>

<details>
<summary><b>Install options and uninstall</b></summary>

From a terminal instead of inside Claude Code:

```bash
claude plugin marketplace add Sagor31h2/claude-auto-route && claude plugin install auto-route@auto-route
```

Update with `claude plugin update auto-route@auto-route`, then restart. Uninstall with `/plugin uninstall auto-route@auto-route`; optionally remove local files:

```bash
rm -f ~/.claude/auto-route.on ~/.claude/auto-route.log ~/.claude/auto-route.err ~/.claude/auto-route.stats
```

(Use `$CLAUDE_CONFIG_DIR` instead of `~/.claude` if it is set.)

</details>

<details>
<summary><b>Troubleshooting</b></summary>

- **Nothing is routed / agents missing**: restart Claude Code after install or update. If installed via `npx skills add` without the agent definitions, routing falls back to `general-purpose` with the model only and announces `Route: sonnet (effort not set: plugin agents missing)`.
- **Always-on seems inactive**: check `/auto-route:auto-route status`, and that `jq` is on your PATH (hooks need it).
- **Prompt ran inline**: pure chat and tiny tasks run inline by design; force delegation with `/auto-route:auto-route <task>`.
- **No stats**: logging is off until `stats on`, and needs `jq`. Hook failures are appended to `~/.claude/auto-route.err` and shown by `stats`.

</details>

<details>
<summary><b>Contributing</b></summary>

Tests need `bash` and `jq`:

```bash
for t in tests/*.test.sh; do bash "$t"; done
claude plugin validate .
claude plugin eval . --runs 1 --ablation none --scaffold --trust-plugin --no-publish   # cases in evals/
```

Layout: `.claude-plugin/plugin.json` (manifest), `agents/` (effort subagents), `hooks/` (always-on, log-route, log-inline), `skills/auto-route/` (`SKILL.md`, `manage.sh`, `stats.sh`), `tests/`, `evals/`.

</details>

## License

MIT © [sagor](https://github.com/Sagor31h2)
