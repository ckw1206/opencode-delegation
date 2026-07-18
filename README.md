# opencode-delegation

A Claude Code skill that delegates hands-on implementation to
[OpenCode](https://opencode.ai) (via an opencode-mcp server) while Claude
orchestrates: per-task dispatch with fresh OpenCode sessions, file handoffs
(task brief → implementer report → review package), a per-task review gate run
by a Claude reviewer subagent (spec compliance + code quality), a durable
progress ledger, and a final whole-branch review.

The dispatch process is adapted from the
[superpowers](https://github.com/obra/superpowers) plugin's
`subagent-driven-development` skill; the scripts in `scripts/` are unmodified
copies from superpowers 6.1.1.

## Layout

- [SKILL.md](SKILL.md) — the skill itself (process, dispatch mechanics, red flags)
- [opencode-implementer-prompt.md](opencode-implementer-prompt.md) — per-task message template for the OpenCode session
- [task-reviewer-prompt.md](task-reviewer-prompt.md) — Claude reviewer subagent template
- `scripts/` — `task-brief`, `review-package`, `sdd-workspace` (bash)

## Install

Copy this directory to `~/.claude/skills/opencode-delegation/`. Requires the
opencode-mcp server to be connected in the session.
