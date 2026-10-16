# opencode-delegation

A skill for coding agents that delegates hands-on implementation to
[OpenCode](https://opencode.ai) (via an opencode-mcp server, or headless via
the `opencode` CLI) while the agent orchestrates: per-task dispatch with fresh
OpenCode sessions, file handoffs (task brief → implementer report → review
package), a per-task review gate run by a reviewer subagent (spec compliance +
code quality), a durable progress ledger, and a final whole-branch review.

The dispatch process follows the subagent-driven-development pattern: one
fresh implementer session per task, a review gate after every task, durable
progress that survives session compaction, and a whole-branch review before
the work is called done.

## Layout

- [SKILL.md](SKILL.md) — the skill itself (process, dispatch mechanics, red flags)
- [opencode-implementer-prompt.md](opencode-implementer-prompt.md) — per-task message template for the OpenCode session
- [task-reviewer-prompt.md](task-reviewer-prompt.md) — reviewer subagent template
- `scripts/` — `task-brief`, `review-package`, `sdd-workspace` (bash)
- `scripts/oc-dispatch` — runs one task headless via `opencode run` in its own
  worktree and prints a JSON result; no MCP server needed
- `.opencode/agents/implementer.md` — the restricted OpenCode agent
  `oc-dispatch` uses (no push, no cluster/SSH access, no `.env` reads)
- `tests/oc-dispatch.sh` — self-check for `oc-dispatch` against a stub `opencode`

## Installation

```bash
npx skills add ckw1206/opencode-delegation -g
```

This uses the [skills CLI](https://github.com/vercel-labs/skills), which
fetches this repo from GitHub and installs it for the agents you pick (Claude
Code, Codex, Cursor, OpenCode, Gemini CLI, Hermes, and more), linking each one
to a single copy. `-a claude-code -a codex …` picks agents without the prompt;
drop `-g` to install into the current project instead of your home directory.

Manual alternative: clone this repo into your agent's skills directory as
`opencode-delegation/`, e.g. `~/.claude/skills/opencode-delegation`.

Requirements:

- The orchestrating agent must be able to dispatch fresh subagent sessions —
  the per-task review gate runs in one.
- `bash` and `git` on the orchestrator's `PATH` (the helpers in `scripts/`);
  `oc-dispatch` also needs `jq`
- [OpenCode](https://opencode.ai) reachable — either the `opencode` CLI
  (the `oc-dispatch` flow) or the opencode-mcp server connected to the agent
  (the MCP flow)
- Keep the directory intact: `SKILL.md` runs the helpers in `scripts/`, and
  `oc-dispatch` loads the implementer agent from `.opencode/`
