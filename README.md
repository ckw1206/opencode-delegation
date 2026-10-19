# opencode-delegation

A skill for coding agents that delegates hands-on implementation to
[OpenCode](https://opencode.ai) (headless, via the `opencode` CLI) while the
agent orchestrates: per-task dispatch with fresh
OpenCode sessions (independent tasks in parallel), file handoffs (task brief → implementer report → review
package), a per-task review gate run by a reviewer subagent (spec compliance +
code quality), a durable progress ledger, and a final whole-branch review.

The dispatch process follows the subagent-driven-development pattern: one
fresh implementer session per task, a review gate after every task, durable
progress that survives session compaction, and a whole-branch review before
the work is called done.

## Layout

- [SKILL.md](SKILL.md) — the skill itself (process, dispatch mechanics, red flags)
- [task-reviewer-prompt.md](task-reviewer-prompt.md) — reviewer subagent template
- `scripts/` — `task-brief`, `review-package`, `sdd-workspace` (bash)
- `scripts/oc-dispatch` — runs one task headless via `opencode run` in its own
  worktree and prints a JSON result; `--resume` continues a task in a fresh
  session after a context overflow
- `scripts/oc-cleanup` — removes merged task worktrees and branches, lists the
  unmerged ones
- `.opencode/agents/implementer.md` — the restricted OpenCode agent
  `oc-dispatch` uses (no push, no cluster/SSH or container-runtime access, no
  `.env` reads, no printing its environment)
- `tests/oc-dispatch.sh`, `tests/oc-cleanup.sh` — self-checks (`oc-dispatch`
  runs against a stub `opencode`)

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
- The [OpenCode](https://opencode.ai) CLI installed and logged in to a
  provider (`opencode providers login`). The skill checks for `opencode` and
  `jq` on its first dispatch and stops to tell you if either is missing; it
  won't install them for you.
- If the implementer's model is one you defined yourself under `provider` in
  your OpenCode config (a self-hosted or OpenAI-compatible endpoint), declare
  its limits there. Without them OpenCode can't compact a session before the
  context window fills, and long tasks end in `ContextOverflowError`:

  ```json
  "provider": {
    "my-provider": {
      "models": {
        "my-model": { "limit": { "context": 262144, "output": 32768 } }
      }
    }
  }
  ```

  Use your model's real numbers. `oc-dispatch` warns when they're missing.
  Models from OpenCode's built-in providers already carry their limits.
- The implementer agent denies container runtimes (`docker`, `podman`),
  because a container can mount the host filesystem around every other rule.
  If your tests need one, start it yourself before dispatching, or adjust
  `.opencode/agents/implementer.md` knowingly.
- Keep the directory intact: `SKILL.md` runs the helpers in `scripts/`, and
  `oc-dispatch` loads the implementer agent from `.opencode/`
