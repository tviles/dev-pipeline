# dev-pipeline

AI development workflow plugin for Claude Code — routes coding tasks through specialized cookbooks (research, plan, implement, review, debug, commit, PR, triage) with agent-scoped safety hooks, autonomous rule enforcement, and task-list persistence.

## What's included

### Skills
- **dev-pipeline** — primary router; dispatches to 10 cookbooks based on user intent (research, investigate, prd, plan, implement, review, debug, commit, pr, issue)
- **save-task-list** — persist task list state across sessions via SessionStart hook
- **triage** — autonomous GitHub issue triage with label validation
- **rulecheck** — autonomous rule adherence checker; finds violations, fixes them in a worktree, opens a PR
- **replicate-issue** — reproduce GitHub issues via browser automation

### Agents
- **Workflow agents (7):** web-researcher, codebase-explorer, codebase-analyst, code-reviewer, silent-failure-hunter, pr-test-analyzer, code-simplifier
- **Specialized agents (2):** triage-agent, rulecheck-agent

### Commands
- `/commit` — atomic commits with conventional formatting
- `/plan-feature` — comprehensive implementation planning
- `/execute` — implement a plan file
- `/validate` — run the validation suite
- `/handoff` — session boundary documentation

### Plugin hooks
- `SessionStart` — restore saved task lists if `CLAUDE_CODE_TASK_LIST_ID` is set
- `PreToolUse` — block dangerous bash commands (scoped to rulecheck-agent via `agent_type` self-filtering)
- `PostToolUse` — auto lint-fix (rulecheck-agent), label validation (triage-agent)
- `SubagentStop` — Slack notification + meta-judge evaluation (rulecheck-agent)

## Installation

```
/plugin marketplace add tviles/claude-plugins
/plugin install dev-pipeline@tviles-plugins
```

## Quick start

After installation, the dev-pipeline skill activates on most coding tasks:

| Intent | Example |
|--------|---------|
| Research | "How does the auth middleware work?" |
| Investigate | "Should we use Drizzle or Prisma?" |
| Plan | "Plan the migration from REST to GraphQL" |
| Implement | "Implement .claude/dev-pipeline/plans/auth.plan.md" |
| Review | "Review PR #42" |
| Debug | "Why is the streaming test failing?" |
| Commit | "Commit these changes" |
| PR | "Create a PR for this branch" |
| Issue | "File a gh issue for this bug" |

## Requirements

- `gh` (GitHub CLI) — for PR/issue commands and triage
- `jq` — for hook scripts
- `git`

### Optional
- `bun` / `pnpm` / `yarn` / `npm` — auto-detected by validate command
- `agent-browser` (`npm install -g agent-browser`) — for the replicate-issue skill
- `SLACK_WEBHOOK_URL` env var — for rulecheck Slack notifications

## License

MIT
