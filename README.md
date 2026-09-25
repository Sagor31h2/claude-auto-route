# auto-route

Claude Code plugin that picks a model and reasoning effort per task, then delegates to a subagent running that combination.

## Overview

Small or mechanical tasks don't need the most expensive model at the highest effort. Before delegating, it prints the choice so you always see why:

```
> Rename this variable everywhere
Route: sonnet + low (mechanical rename across many files)
```

Use it per task, or turn it on once to route every prompt automatically.

## Installation

Inside Claude Code (or `claude` from a terminal, in place of the leading `/`):

```
/plugin marketplace add Sagor31h2/claude-auto-route
/plugin install auto-route@auto-route
```

Restart Claude Code after installing.

## Usage

| Command | Action |
|---|---|
| `/auto-route:auto-route <task>` | Route one task |
| `/auto-route:auto-route on` | Route every prompt automatically |
| `/auto-route:auto-route off` | Back to manual (default) |
| `/auto-route:auto-route status` | Show whether always-on is enabled |
| `/auto-route:auto-route stats` | Runs, tokens and average duration per route |
| `/auto-route:auto-route reset` | Reset stats log |

Always-on is controlled by the flag file `~/.claude/auto-route.on` (under `$CLAUDE_CONFIG_DIR` if set), which the `on`/`off` commands create or remove, or which can be toggled directly with `touch`/`rm`. When enabled, every prompt must invoke the auto-route skill before any tool call, except a pure chat answer that needs no tools (answered inline starting with `Route: inline (<reason>)`). Slash commands and short conversational replies like "ok", "stop", or "looks good" are skipped entirely.

## How it works

Tasks are evaluated on two independent axes:

| Axis | Options | Question it answers |
|---|---|---|
| Model | `haiku`, `sonnet`, `opus` | Capability or knowledge needed |
| Effort | `low`, `medium`, `high`, `xhigh` (plus `max` only as the last retry) | Step-by-step reasoning needed |

Claude Code reads effort only from an agent's frontmatter, so the plugin ships five agents (`auto-route:effort-low` through `auto-route:effort-max`) with a fixed effort and `model: inherit`; the skill picks one and passes the model per call (12 first-pick combinations plus `opus` + `max`). A mechanical rename across many files, for example, routes to `sonnet` + `low`.

Work is split into phases, each with a route range that the rubric picks within by task size and risk:

| Phase | Route range |
|---|---|
| Plan | `sonnet` + `effort-medium` (small, clear) to `opus` + `effort-xhigh` (architecture, migrations) |
| Research | `haiku` + `effort-low` to `sonnet` + `effort-medium` |
| Implement | Rubric |
| Debug | `sonnet` + `effort-high` to `opus` + `effort-xhigh` |
| Review | `sonnet` + `effort-medium` (small diff) to `opus` + `effort-high` (security, concurrency, many files) |

Plan, Research and Review are read-only. The planner runs once and returns 3-5 steps; each step runs on its own route with earlier results passed along, in parallel only for independent steps on disjoint files. In Claude Code plan mode it stops for approval, and a Review follows risky or multi-file plans.

Other rules: pure chat and tiny tasks that depend on the current conversation are answered inline; when unsure on an axis it takes the higher value; one retry for capability failures, one step up on the axis that fell short (effort up to xhigh, model up to opus, opus + max only after opus + xhigh); permission and environment errors are reported, not retried.

`/model opusplan` covers the main session; auto-route covers delegated work.

Claude Fable is not used: it costs $10/$50 per million input/output tokens vs $4/$20 for Opus 5.5, which matches or beats it on most benchmarks and, unlike Fable, accepts per-turn effort ([Pricing](https://platform.claude.com/docs/en/about-claude/pricing), [The Decoder](https://the-decoder.com/claude-opus-5-5-matches-fable-5-1-at-40-percent-lower-cost-as-anthropic-promises-to-fix-claudish-writing/), [Effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)).

Routing happens through subagents rather than switching the session's effort mid-conversation: effort is part of the prompt cache key, so per-prompt switching re-reads the conversation uncached; `effortLevel` is only re-read from the global `~/.claude/settings.json`, so rewriting it affects every open session ([issue #95347](https://github.com/anthropics/claude-code/issues/95347)). Subagents have their own context, so per-task choices cost nothing extra and don't touch other sessions.

### Stats

Each routed call appends one line to `~/.claude/auto-route.log` (or under `$CLAUDE_CONFIG_DIR`) with time, model, effort, resolved model, tokens and duration, no prompt or task text. Logged when the subagent finishes (not at launch), so it works the same for synchronous and backgrounded calls; tokens and duration come from the subagent's own transcript, tokens being the final turn's total. Fields can be empty if the transcript can't be read. Needs `jq` (without it nothing is logged). Reset with `/auto-route:auto-route reset` or by deleting the file. Hooks run through bash (on Windows, Git Bash).

## Troubleshooting

**Routing not happening in a session**

- Always-on is a nudge, not a hard override: it can still answer a pure chat question or a tiny task inline instead of delegating. Force routing for a specific task with `/auto-route:auto-route <task>`.
- Edits to this repo don't reach a running session: it uses the installed copy under `~/.claude/plugins/cache/auto-route/auto-route/<version>`. Update the plugin (see "Update" below) and restart Claude Code.
- Confirm always-on is actually on with `/auto-route:auto-route status`, or check that `~/.claude/auto-route.on` exists.

## Limitations

- The main session keeps its own model and effort (only delegated work is routed).
- Choosing a route and relaying results costs some main-session tokens.

## Update

```
claude plugin marketplace update auto-route
claude plugin update auto-route@auto-route
```

Restart Claude Code after updating.

## Uninstall

```
claude plugin uninstall auto-route@auto-route
```

This leaves `~/.claude/auto-route.on` and `~/.claude/auto-route.log` (or their `$CLAUDE_CONFIG_DIR` equivalents) in place; remove them manually for no trace left behind.

## Contributing

Fork, branch, make your change, then:

1. Run the tests: `bash tests/always-on.test.sh` and `bash tests/log-route.test.sh`.
2. Validate the plugin manifest: `claude plugin validate .`.
3. Optionally run the evals: `claude plugin eval . --runs 1 --ablation none --scaffold --trust-plugin --no-publish` (about $0.60; hitting the 150-second timeout after the first delegation is expected).
4. Bump the version in `.claude-plugin/plugin.json` and open a pull request.

File layout:

```
.claude-plugin/plugin.json
agents/effort-{low,medium,high,xhigh,max}.md
hooks/always-on.sh, log-route.sh
skills/auto-route/SKILL.md, stats.sh
tests/always-on.test.sh, log-route.test.sh
evals/debug-deadlock/, plan-multistep/, pure-chat/, research-lookup/, typo-fix/
```

## License

MIT, see [LICENSE](LICENSE).
