# auto-route

A Claude Code plugin that picks the model and the reasoning effort for each task separately, then hands the task to a subagent running that combination.

## How it works

Each task is scored on two independent axes:

| Axis | Options | Question it answers |
|---|---|---|
| Model | `haiku`, `sonnet`, `opus` | How much capability or knowledge does the task need? |
| Effort | `low`, `medium`, `high`, `xhigh` | How much step-by-step reasoning does the task need? |

Examples:

| Task | Route |
|---|---|
| Fix a typo | `haiku` + `low` |
| Find where a function is defined | `haiku` + `low` |
| Add a feature in a known file | `sonnet` + `medium` |
| Small but subtle race condition | `sonnet` + `xhigh` |
| Large but mechanical rename across many files | `sonnet` + `low` |

Claude Code reads effort only from an agent's frontmatter, so the plugin ships four agents (`effort-low` to `effort-xhigh`), each with a fixed effort and `model: inherit`. The skill chooses one of them and passes the model per call, which gives 12 combinations.

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

Before delegating, Claude prints the choice in one line, e.g. `Route: sonnet + high (unknown-cause bug in known file)`.

Routing rules:
- Claude answers inline instead of delegating for pure chat and for tiny tasks that depend on context already in the conversation.

Always-on mode is a `UserPromptSubmit` hook that checks for the flag file `~/.claude/auto-route.on` (or under `$CLAUDE_CONFIG_DIR` if set). You can also toggle it with `touch` or `rm` on that file.

## Limitations

- Your main session keeps its own model and effort; only the delegated work runs on the chosen combination (see Why subagents, not session effort).
- The main session still spends some tokens choosing the route and relaying the result.
- `max` effort isn't included. Add an `agents/effort-max.md` if you need it.

## Update and uninstall

```
claude plugin marketplace update auto-route
claude plugin update auto-route@auto-route
claude plugin uninstall auto-route@auto-route
```

## License

MIT, see [LICENSE](LICENSE).
