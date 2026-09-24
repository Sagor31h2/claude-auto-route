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
| Add a feature in a known file | `sonnet` + `medium` |
| Small but subtle race condition | `sonnet` + `xhigh` |
| Large but mechanical migration | `opus` + `low` |

Claude Code reads effort only from an agent's frontmatter, so the plugin ships four agents (`effort-low` to `effort-xhigh`), each with a fixed effort and `model: inherit`. The skill chooses one of them and passes the model per call, which gives 12 combinations.

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

Before delegating, Claude prints the choice in one line, e.g. `Route: sonnet + high (unknown-cause bug in known file)`. Pure chat questions are answered directly, without delegation.

Always-on mode is a `UserPromptSubmit` hook that checks for the flag file `~/.claude/auto-route.on`. You can also toggle it with `touch` or `rm` on that file.

## Limitations

- Your main session's model and effort don't change. Claude Code can't switch them mid-session, so only the delegated work runs on the chosen combination.
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
