# opencode-delegation

A Claude Code skill that delegates hands-on implementation to
[OpenCode](https://opencode.ai) (via an opencode-mcp server) while Claude
orchestrates: per-task dispatch with fresh OpenCode sessions, file handoffs
(task brief → implementer report → review package), a per-task review gate run
by a Claude reviewer subagent (spec compliance + code quality), a durable
progress ledger, and a final whole-branch review.

The dispatch process is adapted from the
[superpowers](https://github.com/obra/superpowers) plugin's
`subagent-driven-development` skill; the scripts in `scripts/` started as
copies from superpowers 6.1.1 (since patched: section-bounded briefs that
include Global Constraints, empty-range guard in `review-package`).
Requires the superpowers plugin for `requesting-code-review` and
`finishing-a-development-branch`.

## Layout

- [SKILL.md](SKILL.md) — the skill itself (process, dispatch mechanics, red flags)
- [opencode-implementer-prompt.md](opencode-implementer-prompt.md) — per-task message template for the OpenCode session
- [task-reviewer-prompt.md](task-reviewer-prompt.md) — Claude reviewer subagent template
- `scripts/` — `task-brief`, `review-package`, `sdd-workspace` (bash)
- `scripts/oc-dispatch` — runs one task headless via `opencode run` in its own
  worktree and prints a JSON result; no MCP server needed
- `.opencode/agents/implementer.md` — the restricted OpenCode agent
  `oc-dispatch` uses (no push, no cluster/SSH access, no `.env` reads)
- `tests/oc-dispatch.sh` — self-check for `oc-dispatch` against a stub `opencode`

## Install

Copy this directory to `~/.claude/skills/opencode-delegation/`. Requires the
opencode-mcp server to be connected in the session.
