# auto-route

Claude Code plugin that picks the model (haiku / sonnet / opus) and reasoning effort (low / medium / high / xhigh) for each task separately, then hands the task to a subagent with that combination.

## Install

```
claude plugin marketplace add <path-or-git-url-of-this-repo>
claude plugin install auto-route@auto-route
```

Restart Claude Code after installing.

## Use

- `/auto-route:auto-route <task>`: route one task
- `/auto-route:auto-route on`: route every prompt automatically
- `/auto-route:auto-route off`: back to manual
- `/auto-route:auto-route status`: show the current state

Your main session's model does not change. Claude Code can't switch it mid-session, so only the delegated work runs on the chosen model and effort.
