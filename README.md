# auto-route

auto-route picks the Claude model and reasoning effort for each task separately. It hands the task to a subagent configured with that combination.

`Route: sonnet + high (unknown-cause bug in known file)`

## Quick start

Install inside Claude Code:

```
/plugin marketplace add Sagor31h2/claude-auto-route
/plugin install auto-route@auto-route
```

or from a terminal:

```
claude plugin marketplace add Sagor31h2/claude-auto-route
claude plugin install auto-route@auto-route
```

Then restart Claude Code, try `/auto-route:auto-route <task>`, and optionally `/auto-route:auto-route on` to route every prompt.

## Commands

| Command | Action |
|---|---|
| `/auto-route:auto-route <task>` | Route one task |
| `/auto-route:auto-route on` | Route every prompt automatically |
| `/auto-route:auto-route off` | Back to manual (default) |
| `/auto-route:auto-route status` | Show whether always-on is enabled |
| `/auto-route:auto-route stats` | Runs, tokens and average duration per route |
| `/auto-route:auto-route reset` | Reset stats log |

Always-on uses the flag file `~/.claude/auto-route.on` (under `$CLAUDE_CONFIG_DIR` if set), can also be toggled with touch/rm, and skips slash commands and short conversational replies or interruptions like "ok", "yes, continue", "stop", "cancel", or "looks good".

## How routing works

Tasks are evaluated on two independent axes:

| Axis | Options | Question it answers |
|---|---|---|
| Model | `haiku`, `sonnet`, `opus` | Capability or knowledge needed |
| Effort | `low`, `medium`, `high`, `xhigh` (plus `max` only as the last retry) | Step-by-step reasoning needed |

Claude Code reads effort only from an agent's frontmatter, so the plugin ships five agents (`auto-route:effort-low` through `auto-route:effort-max`) with a fixed effort and `model: inherit`; the skill picks one and passes the model per call (12 first-pick combinations plus `opus` + `max`).

| Task | Route |
|---|---|
| Fix a typo | `haiku` + `low` |
| Find a definition | `haiku` + `low` |
| Feature in a known file | `sonnet` + `medium` |
| Small but subtle race condition | `sonnet` + `xhigh` |
| Mechanical rename across many files | `sonnet` + `low` |

Phases and default routes:

| Phase | Default route |
|---|---|
| Plan | `opus` + `effort-high` (`effort-xhigh` for architecture or migrations) |
| Research | `haiku` or `sonnet` + `effort-low` / `effort-medium` |
| Implement | Rubric |
| Debug | `sonnet` or `opus` + `effort-high` / `effort-xhigh` |
| Review | `sonnet` + `effort-high` |

Plan, Research and Review are read-only.

Opus + high plans once in 3-5 steps. Each step runs on its own route with earlier results passed along, running in parallel only for independent steps on disjoint files. In Claude Code plan mode it stops for approval, and a Review follows risky or multi-file plans.

Rules:
- Pure chat and tiny tasks that depend on the current conversation are answered inline.
- When unsure on an axis it takes the higher value.
- One retry for capability failures, one step up on the axis that fell short (effort up to xhigh, model up to opus, opus + max only after opus + xhigh).
- Permission and environment errors are reported, not retried.

For planning in the main session, `/model opusplan` covers the main session, auto-route covers delegated work.

Claude Fable is not used because it costs $10/$50 per million input/output tokens vs $4/$20 for Opus 5.5, while Opus 5.5 matches or beats it on most benchmarks ([Pricing](https://platform.claude.com/docs/en/about-claude/pricing), [The Decoder](https://the-decoder.com/claude-opus-5-5-matches-fable-5-1-at-40-percent-lower-cost-as-anthropic-promises-to-fix-claudish-writing/)). In addition, it doesn't accept per-turn effort ([Effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)).

## Why subagents, not session effort

- Effort is part of the prompt cache key so per-prompt switching re-reads the conversation uncached.
- `effortLevel` is only re-read from the global `~/.claude/settings.json`, so rewriting it affects every open session ([issue #95347](https://github.com/anthropics/claude-code/issues/95347)).
- Subagents have their own context, so per-task choices cost nothing extra and don't touch other sessions.

## Stats

Each routed call appends one line to `~/.claude/auto-route.log` (or under `$CLAUDE_CONFIG_DIR`) with time, model, effort, resolved model, tokens and duration, and no prompt or task text. Logging happens when the subagent finishes (not at launch), so it works the same for a synchronous call and a backgrounded one; tokens and duration are computed from the subagent's own transcript; tokens is the final turn's total (the same figure Claude Code reports for the subagent). Fields can be empty if the transcript can't be read. Needs `jq` (without it nothing is logged). Reset with `/auto-route:auto-route reset` or by deleting the file. Hooks run through bash (on Windows, Git Bash).

## Limitations

- The main session keeps its own model and effort (only delegated work is routed).
- Choosing a route and relaying results costs some main-session tokens.

## Development

Validate with `claude plugin validate .`.

Run evals:

```
claude plugin eval . --runs 1 --ablation none --scaffold --trust-plugin --no-publish
```

The `--scaffold` flag runs each case's scaffold.sh, which stages small fixture files, as you. Graders check the actual Agent call (model and subagent_type) and the Route: line. The chat case checks that no subagent is called. A full run costs about $0.60. Hitting the 150-second timeout after the first delegation is expected.

File layout:

```
.claude-plugin/
  plugin.json
agents/
  effort-low.md
  effort-medium.md
  effort-high.md
  effort-xhigh.md
  effort-max.md
hooks/
  always-on.sh
  log-route.sh
skills/
  auto-route/
    SKILL.md
    stats.sh
evals/
  debug-deadlock/
  plan-multistep/
  pure-chat/
  research-lookup/
  typo-fix/
```

## Update and uninstall

```
claude plugin marketplace update auto-route
claude plugin update auto-route@auto-route
claude plugin uninstall auto-route@auto-route
```

## License

MIT, see [LICENSE](LICENSE).
