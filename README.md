# auto-route

A Claude Code plugin that picks the model and the reasoning effort for each task separately, then hands the task to a subagent running that combination.

## How it works

Each task is scored on two independent axes:

| Axis | Options | Question it answers |
|---|---|---|
| Model | `haiku`, `sonnet`, `opus` | How much capability or knowledge does the task need? |
| Effort | `low`, `medium`, `high`, `xhigh` (plus `max` as a last retry) | How much step-by-step reasoning does the task need? |

Examples:

| Task | Route |
|---|---|
| Fix a typo | `haiku` + `low` |
| Find where a function is defined | `haiku` + `low` |
| Add a feature in a known file | `sonnet` + `medium` |
| Small but subtle race condition | `sonnet` + `xhigh` |
| Large but mechanical rename across many files | `sonnet` + `low` |

Claude Code reads effort only from an agent's frontmatter, so the plugin ships five effort agents (`effort-low` to `effort-max`), each with a fixed effort and `model: inherit`; the skill picks one and passes the model per call, giving 12 first-pick combinations plus `opus` + `max` as the last retry.

### Why not fable

Claude Fable 5.1 costs $10/$50 per million input/output tokens against $4/$20 for Opus 5.5, Opus 5.5 matches or beats it on most benchmarks (for example Terminal-Bench 66.4% vs 55.8%), and Fable doesn't accept per-turn effort, which the effort agents rely on. Fable's strength is multi-hour unattended runs, which isn't what per-task routing is for. Sources as markdown links: [Pricing](https://platform.claude.com/docs/en/about-claude/pricing), [The Decoder: Opus 5.5 vs Fable 5.1](https://the-decoder.com/claude-opus-5-5-matches-fable-5-1-at-40-percent-lower-cost-as-anthropic-promises-to-fix-claudish-writing/), [Effort docs](https://platform.claude.com/docs/en/build-with-claude/effort).

## Phases

Tasks are sorted into a phase first — Plan, Research, Implement, Debug, Review:

| Phase | Default route |
|---|---|
| Plan | `opus` + `effort-high` (`effort-xhigh` for architecture or migrations) |
| Research | `haiku` or `sonnet` + `effort-low`/`effort-medium` |
| Implement | Rubric |
| Debug | `sonnet` or `opus` + `effort-high`/`effort-xhigh` |
| Review | `sonnet` + `effort-high` |

For multi-step work, a strong model (opus + high) writes a short plan once, each step then runs on its own cheaper route, and results of earlier steps are passed to later ones. In Claude Code plan mode, it stops after the plan for your approval.

### Planning in the main session

If you plan in the main session with Claude Code's plan mode, `/model opusplan` uses Opus while planning and Sonnet while executing. It works alongside auto-route: opusplan covers the main session, auto-route covers delegated work.

## Why subagents, not session effort

- Claude Code can change the main session's effort (`/effort`, the `effortLevel` setting), but doing it per prompt is costly: effort is part of the prompt cache key, so every switch makes the next turn re-read the whole conversation at full, uncached price.
- The `effortLevel` setting is only re-read live from the global `~/.claude/settings.json`, so a hook that rewrites it on every prompt also changes effort for every other open session (see anthropics/claude-code [issue #95347](https://github.com/anthropics/claude-code/issues/95347)).
- A subagent starts its own context, so choosing its model and effort per task costs nothing extra in cache terms and doesn't touch the main session or other sessions.

## Install

```
claude plugin marketplace add Sagor31h2/claude-auto-route
claude plugin install auto-route@auto-route
```

Restart Claude Code after installing.

## Use

| Command | What it does |
|---|---|
| `/auto-route:auto-route <task>` | Route one task |
| `/auto-route:auto-route on` | Route every prompt automatically |
| `/auto-route:auto-route off` | Back to manual (default) |
| `/auto-route:auto-route status` | Show whether always-on routing is enabled |
| `/auto-route:auto-route stats` | Show runs, tokens and average duration per route |

Before delegating, Claude prints the choice in one line, e.g. `Route: sonnet + high (unknown-cause bug in known file)`.

Routing rules:
- Claude answers inline instead of delegating for pure chat and for tiny tasks that depend on context already in the conversation.

Always-on mode is a `UserPromptSubmit` hook that checks for the flag file `~/.claude/auto-route.on` (or under `$CLAUDE_CONFIG_DIR` if set). You can also toggle it with `touch` or `rm` on that file.

## Stats

Each routed call appends one line to `~/.claude/auto-route.log` (or under `$CLAUDE_CONFIG_DIR`) with the time, model, effort, resolved model, tokens and duration, and no prompt or task text. The stats command summarizes it per route. Token and duration fields come from Claude Code's Agent tool response and can be empty for background or failed calls. Logging needs `jq` (without it nothing is logged); delete the file to reset. Hooks run through bash (on Windows, Git Bash).

## Limitations

- Your main session keeps its own model and effort; only the delegated work runs on the chosen combination (see Why subagents, not session effort).
- The main session still spends some tokens choosing the route and relaying the result.

## Update and uninstall

```
claude plugin marketplace update auto-route
claude plugin update auto-route@auto-route
claude plugin uninstall auto-route@auto-route
```

## Evals

Run the eval suite from the repo root:

```
claude plugin eval . --runs 1 --ablation none --scaffold --trust-plugin --no-publish
```

Each case is defined in a `case.yaml`. Four cases stage small fixture files with a `scaffold.sh` (hence `--scaffold`, which runs those scripts as you). Graders check the actual Agent call (model and subagent_type via a `tool_used` grader) and the one-line `Route:` announcement, and the chat case checks that no subagent is called. A full run costs about $1 (5 cases, one run each). The graders only need the first delegation, so a run hitting its 150-second timeout afterwards is expected and doesn't affect the score.

## License

MIT, see [LICENSE](LICENSE).
