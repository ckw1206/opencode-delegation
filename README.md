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

Installation differs by agent. If you use more than one, install the skill
separately for each one. Every install is the same shape: a folder named
`opencode-delegation` containing `SKILL.md`, placed where the agent discovers
skills.

Requirements for all agents:

- The orchestrating agent must be able to dispatch fresh subagent sessions —
  the per-task review gate runs in one.
- `bash` and `git` on the orchestrator's `PATH` (the helpers in `scripts/`)
- [OpenCode](https://opencode.ai) reachable — either the `opencode` CLI
  (the `oc-dispatch` flow) or the opencode-mcp server connected to the agent
  (the MCP flow)
- Keep the directory intact: `scripts/` is invoked by relative path from
  `SKILL.md`

### Claude Code

Personal (all projects):

```bash
git clone https://github.com/ckw1206/opencode-delegation.git \
  ~/.claude/skills/opencode-delegation
```

For a single project, clone into the repo at `.claude/skills/` instead.

### Cursor

Project-level:

```bash
git clone https://github.com/ckw1206/opencode-delegation.git \
  .cursor/skills/opencode-delegation
```

Personal (all projects): clone into `~/.cursor/skills/` instead. Restart the
agent session after installing.

### Codex CLI

```bash
git clone https://github.com/ckw1206/opencode-delegation.git \
  ~/.codex/skills/opencode-delegation
```

`~/.agents/skills/opencode-delegation` works too (the cross-tool alias).

### Hermes Agent

```bash
git clone https://github.com/ckw1206/opencode-delegation.git \
  ~/.hermes/skills/opencode-delegation
```

Restart active Hermes sessions so the skill registers. For a specific profile,
use `~/.hermes/profiles/<name>/skills/` instead.

### OpenCode

OpenCode also discovers `~/.claude/skills/`, so a Claude Code install is
picked up automatically. To install natively:

```bash
git clone https://github.com/ckw1206/opencode-delegation.git \
  ~/.config/opencode/skills/opencode-delegation
```

### Gemini CLI

```bash
git clone https://github.com/ckw1206/opencode-delegation.git \
  ~/.gemini/skills/opencode-delegation
```

### Other agents

Any agent that follows the `SKILL.md` convention can load this from the
cross-tool directory `~/.agents/skills/opencode-delegation/` (supported as an
alias by, among others, Codex, Gemini CLI, and OpenCode).
