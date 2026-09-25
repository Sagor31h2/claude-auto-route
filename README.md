# auto-route

Claude Code plugin that saves tokens and cost by picking a model (`haiku`, `sonnet`, or `opus`) and reasoning effort (`low` to `xhigh`) per task, then delegating to a matching effort-level subagent.

## Overview

Small or mechanical tasks do not need the most expensive model at maximum reasoning effort. Before delegating, the router prints its decision:

```
> Rename this variable everywhere
Route: sonnet + low (mechanical rename across many files)
```

Pure chat and tiny tasks requiring no tools run inline: `Route: inline (<reason>)`. Route tasks on demand, or enable always-on mode to route every prompt automatically.

## Installation

Inside Claude Code (or `claude` from a terminal without the leading `/`):

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

Always-on is controlled by the flag file `~/.claude/auto-route.on` (under `$CLAUDE_CONFIG_DIR` if set), created or removed by `on`/`off`, or toggled with `touch`/`rm`. When enabled, the hook tells Claude to invoke the auto-route skill before any tool call. It skips slash commands, short acknowledgements (`ok`, `stop`, `looks good`), and greetings or thanks (`hi`, `hello`, `thanks`, `bye`), while greeting-prefixed tasks (`hi, fix the bug`) still route. Pure chat answers needing no tools run inline starting with `Route: inline (<reason>)`.

## How it works

Tasks are evaluated on two independent axes:

| Axis | Options | Question it answers |
|---|---|---|
| Model | `haiku`, `sonnet`, `opus` | Capability or knowledge needed |
| Effort | `low`, `medium`, `high`, `xhigh` (plus `max` on last retry) | Step-by-step reasoning needed |

Claude Code reads effort only from an agent's frontmatter, so the plugin ships five agents (`auto-route:effort-low` through `auto-route:effort-max`) with fixed effort and `model: inherit`; the skill selects one and passes the model per call (12 combinations plus `opus` + `max`). For skill-only installs (e.g. via `npx skills add` on skills.sh) where effort agents are missing, it delegates to `general-purpose` with model only, noting `(effort not set: plugin agents missing)` in the route line.

Work is split into phases, each with a route range that the rubric picks within by task size and risk:

| Phase | Route range |
|---|---|
| Plan | `sonnet` + `effort-medium` (small, clear) to `opus` + `effort-xhigh` (architecture, migrations) |
| Research | `haiku` + `effort-low` to `sonnet` + `effort-medium` |
| Implement | Rubric |
| Debug | `sonnet` + `effort-high` to `opus` + `effort-xhigh` |
| Review | `sonnet` + `effort-medium` (small diff) to `opus` + `effort-high` (security, concurrency, many files) |

Plan, Research and Review are read-only. The planner runs once and returns 3-5 steps; each step runs on its own route with earlier results passed along, in parallel only for independent steps on disjoint files. In Claude Code plan mode it stops for approval, and a Review follows risky or multi-file plans.

Other rules: pure chat and tiny tasks depending on current context run inline; when unsure on an axis, take the higher value; capability failures retry at most once, stepping up one level on the failing axis (effort up to xhigh, model up to opus, opus + max only after opus + xhigh); permission and environment errors are reported without retry.

`/model opusplan` covers the main session; auto-route covers delegated work.

Claude Fable is not used: it costs $10/$50 per million input/output tokens vs $4/$20 for Opus 5.5, which matches or beats it on most benchmarks and, unlike Fable, accepts per-turn effort ([Pricing](https://platform.claude.com/docs/en/about-claude/pricing), [The Decoder](https://the-decoder.com/claude-opus-5-5-matches-fable-5-1-at-40-percent-lower-cost-as-anthropic-promises-to-fix-claudish-writing/), [Effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)).

Routing uses subagents rather than switching session effort mid-conversation: effort is part of the prompt cache key, so per-prompt switching invalidates the cache; `effortLevel` is only re-read from `~/.claude/settings.json`, so changing it affects all open sessions ([issue #95347](https://github.com/anthropics/claude-code/issues/95347)). Subagents have their own context, so per-task choices cost nothing extra and don't touch other sessions.

### Stats

Each routed call appends one line to `~/.claude/auto-route.log` (or `$CLAUDE_CONFIG_DIR`) with timestamp, model, effort, resolved model, tokens, and duration (no prompt text). Logged on subagent finish from its transcript for both synchronous and background calls (tokens = final turn total). Fields can be empty if the transcript can't be read. Requires `jq`; without it nothing is logged. Reset with `/auto-route:auto-route reset` or by removing the file. Hooks run in bash (Git Bash on Windows).

## Troubleshooting

- **Routing not delegating**: Always-on instructs Claude to invoke the skill, but pure chat or tiny tasks run inline. Force delegation with `/auto-route:auto-route <task>`.
- **Always-on inactive**: Confirm with `/auto-route:auto-route status` or check that `~/.claude/auto-route.on` exists.
- **Local edits not reflected**: Running sessions use `~/.claude/plugins/cache/auto-route/auto-route/<version>`. Update the plugin (see Update) and restart Claude Code.

## Limitations

- The main session retains its own model and effort (only delegated work is routed).
- Token overhead (`claude plugin details`): ~290 tokens per session always, ~40 per prompt from the always-on hook, ~1.8k per skill invocation, and ~70 per subagent.

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

This leaves `~/.claude/auto-route.on` and `~/.claude/auto-route.log` (or `$CLAUDE_CONFIG_DIR` equivalents) in place; remove them manually for no trace left behind.

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
