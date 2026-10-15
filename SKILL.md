---
name: opencode-delegation
description: >-
  Use when the user wants OpenCode (via the opencode-mcp server) to do the
  hands-on coding — building a feature, fixing a bug, refactoring, writing a
  script, or any multi-step implementation task. Triggers include "have OpenCode
  build this", "delegate this to OpenCode", "use OpenCode to implement", or
  OpenCode delegation being the established working mode for the project. Use
  even when the user names only the implementation, not the review process.
---

# OpenCode Development Delegation

Execute a plan by dispatching a fresh OpenCode session per task, a task review
(spec compliance + code quality) by a Claude reviewer subagent after each, and
a broad whole-branch review at the end.

**Core principle:** fresh OpenCode session per task + task review (spec +
quality) + broad final review = high quality, fast iteration.

## When not to use

- The user wants *you* to implement — delegation wasn't requested and isn't the
  established mode. Just do the work.
- Pure questions, reviews of existing code, or research with no implementation
  to delegate.

## The division of labor

Three separate hands, so nobody grades their own homework:

- **OpenCode implements.** It writes code, writes tests, runs them, commits.
- **A Claude reviewer subagent reviews** each task's diff — a different engine
  from the implementer, dispatched fresh per review with no sunk cost in the
  code.
- **You are the controller and staff engineer.** You pressure-test the plan,
  curate exactly the context each dispatch needs, adjudicate review findings,
  and you alone decide when the work is done.

**Do not write or edit implementation code yourself** — if something is wrong,
articulate *what* and *why* clearly enough that OpenCode fixes it. Your hands
stay on the inspection tools (reading files, diffs, running the test suite to
verify claims); OpenCode's hands stay on the keyboard.

**Narration:** between tool calls, narrate at most one short line — the ledger
and the tool results carry the record.

**Continuous execution:** do not pause to check in with the user between
tasks. The only reasons to stop are: a BLOCKED status you cannot resolve,
ambiguity that genuinely prevents progress, or all tasks complete.

## Talking to OpenCode

OpenCode is reached through the **opencode-mcp** server. Before your first
delegation, look at the tools actually available to you and find the ones whose
names contain `opencode` — the server typically exposes something to send a
prompt/message and get OpenCode's reply, and is usually session-based (a tool
to start or identify a session, then a tool to send turns into it). Use
whatever shape is present rather than assuming a fixed tool name.

If you can't find any `opencode` tool, stop and tell the user the opencode-mcp
server doesn't appear to be connected in this session (a freshly added MCP
usually needs the session restarted before its tools register). Don't silently
fall back to doing the implementation yourself — that defeats the whole purpose.

**Session lifecycle:** one fresh OpenCode session per task. A task's session is
reused for exactly two things — answering that task's NEEDS_CONTEXT questions,
and fix rounds after its review — and is abandoned when the task is marked
complete. The next task starts a new session: a fresh implementer gets its
task, the interfaces it touches, and the global constraints — never the
accumulated history of prior tasks.

Every dispatch is a briefing to a capable colleague who can't see your screen:
where to work, what this step is, the relevant slice of the approved plan, and
the constraints that bind it. Exact values live in the brief file, not the
message.

## Dispatch mechanics (avoid the frozen-call trap)

- **Smoke-test before the first real dispatch.** A health check only proves the
  server is up, not that the chosen provider/model answers. Send one trivial
  prompt (e.g. "reply with the single word READY") and confirm a non-empty
  response comes back before delegating any actual work. If the smoke test
  hangs or returns empty, fix the provider/model choice first — never queue
  real tasks onto an unverified pipe.
- **Never dispatch with a blocking wait-for-completion tool** (e.g.
  `opencode_run`, `opencode_wait`). Implementation turns take minutes; a
  blocking call looks frozen in the user's terminal, gets interrupted, and the
  interrupt registers as a permission rejection — a loop that goes nowhere.
- **Dispatch async instead**: fire-and-forget (e.g. `opencode_fire`) to send
  the task, then poll cheap status (e.g. `opencode_check`) between doing your
  own review prep. Tell the user the task is running and roughly how long.
- **If a dispatch call is denied at the permission prompt**, do not resend the
  identical call. Say once what needs approving (suggest "always allow" for the
  opencode tools), then wait for the user's go-ahead.

## Phase 0 — Get a sound plan

If a written implementation plan already exists for this work, skip to
Pre-flight. Otherwise, have OpenCode produce one — if it exposes a planning
skill (e.g. `/writing-plans`), tell it to use that — covering problem
analysis, requirements, approach, risks and assumptions, test strategy, and
step-by-step tasks.

**Format requirements** (the execution machinery depends on them): the plan is
a markdown file; each task under a `## Task N: <name>` heading containing its
complete requirements; binding cross-task requirements (exact values, formats,
"same layout as X" relationships) in a `## Global Constraints` section.

Then **review the plan as the senior engineer in the room.** Read it against
the actual codebase — open the files it proposes to touch, check that its
assumptions about existing structure hold. Hunt for:

- Weak or unstated assumptions ("assumes the API returns sorted results" — does it?)
- Missing edge cases and failure modes
- Requirements the user implied but the plan dropped
- Architectural choices that will age badly or fight existing patterns
- A test strategy that wouldn't actually catch the bugs that matter here

Send your critique back and iterate until the plan is genuinely sound — not
just until OpenCode stops pushing back. A few rounds here is cheaper than
discovering a design hole after the code is written. When it's solid, say so
explicitly.

## Pre-flight plan review

Before dispatching Task 1, scan the plan once for conflicts: tasks that
contradict each other or the Global Constraints, and anything the plan
explicitly mandates that the review rubric treats as a defect (a test that
asserts nothing, verbatim duplication of a logic block). Present everything
you find to the user as one batched question — each finding beside the plan
text that mandates it, asking which governs. If the scan is clean, proceed
without comment.

Also confirm you're on a working branch — never start implementation on
main/master without explicit user consent.

## Per-task loop

For each task, in order:

1. **Record BASE**: `git rev-parse HEAD`. Reviews diff BASE..HEAD — never
   `HEAD~1`, which silently drops all but the last commit of a multi-commit
   task.
2. **Extract the brief**: run this skill's `scripts/task-brief PLAN_FILE N` —
   it writes the task's full text to a file and prints the path. The brief is
   the single source of requirements; never paste task text into the dispatch.
3. **Dispatch a fresh OpenCode session** using
   [opencode-implementer-prompt.md](opencode-implementer-prompt.md): brief
   path, scene-setting context, working directory, report-file path
   (brief `…/task-N-brief.md` → report `…/task-N-report.md`). Fire async,
   poll while you prep the review.
4. **Handle the status** it replies with:
   - **DONE** → proceed to review.
   - **DONE_WITH_CONCERNS** → read the concerns. Correctness or scope
     concerns get addressed before review; observations get noted and you
     proceed.
   - **NEEDS_CONTEXT** → answer the questions in the same session; it
     continues.
   - **BLOCKED** → if it's a context problem, provide more context in the
     same session. If the task is too large, split it into smaller pieces and
     dispatch each. If the plan itself is wrong, escalate to the user. Never
     ignore an escalation or push the implementer to retry without changing
     something.
5. **Review**: run `scripts/review-package BASE HEAD` (prints the diff-file
   path; the package never enters your context), then dispatch a Claude
   reviewer subagent per [task-reviewer-prompt.md](task-reviewer-prompt.md)
   with the brief, report, and package paths plus the Global Constraints
   copied verbatim. When filling the template: no open-ended directives
   ("check all uses") without a concrete task-specific reason, no re-running
   tests the implementer already ran, and no pre-judging findings — if your
   prompt contains "do not flag" or "at most Minor", stop: let the reviewer
   raise it and adjudicate in the loop.
6. **Act on the verdicts**:
   - Critical/Important findings → send them into the same OpenCode session
     as specific, actionable feedback: file:line, why it's a problem, what
     good looks like. OpenCode fixes, re-runs the covering tests, and appends
     results to its report file. Confirm the fix report names the covering
     tests, the command run, and the output; then regenerate the review
     package for the full BASE..HEAD range and re-review. Repeat until
     approved — never skip the re-review.
   - Minor findings → record in the progress ledger for final-review triage.
     A roll-up nobody reads is a silent discard.
   - ⚠️ "Cannot verify from diff" items → resolve each yourself before
     marking the task complete; you hold the plan and cross-task context the
     reviewer lacks. A confirmed gap is a failed spec review — back to
     OpenCode, then re-review.
   - A finding labeled plan-mandated — or any finding that conflicts with the
     plan's text — is the user's decision: present the finding and the plan
     text, ask which governs.
7. **Mark complete**: append to the ledger (see Durable progress) and update
   your todo list. Next task.

## Final whole-branch review

After all tasks: run `scripts/review-package MERGE_BASE HEAD` (MERGE_BASE =
`git merge-base <base-branch> HEAD` or the branch's start commit) and dispatch a Claude
reviewer subagent on the most capable available model, using
superpowers:requesting-code-review's code-reviewer template, with the package
path and the ledger's accumulated Minor findings so it can triage which must be
fixed before merge.

If it returns findings, dispatch **one** OpenCode fix session with the complete
findings list — not one fixer per finding — then re-review. When clean, use
superpowers:finishing-a-development-branch.

## Durable progress

Conversation memory does not survive compaction; a controller that loses its
place re-dispatches completed work — the most expensive failure there is.
Track progress in a ledger file, not only in todos.

- At skill start, check
  `"$(git rev-parse --show-toplevel)/.superpowers/sdd/progress-<plan-file-basename>.md"`
  (one ledger per plan, so another plan or a superpowers SDD run in the same
  repo can't mark your tasks complete). Tasks
  listed there as complete are DONE — resume at the first task not marked
  complete.
- When a task's review comes back clean, append:
  `Task N: complete (commits <base7>..<head7>, review clean)`.
- After compaction, trust the ledger and `git log` over your own recollection.
- `git clean -fdx` destroys the ledger (it's git-ignored scratch); recover
  from `git log`.

## Final acceptance

Before telling the user it's complete, verify with evidence, not assumption:
the implementation matches the approved plan; the full test suite passes (you
ran it and saw it pass); no unaddressed findings remain. Then summarize:

- **What was implemented** — the change in plain terms.
- **Tests added or updated** — what now protects this behavior.
- **Key design decisions** — the choices worth knowing, and why.
- **Remaining risks** — anything you're watching, or "none" if you mean it.

## Red flags

**Never:**

- Implement or patch code yourself — even when it would be faster
- Silently fall back to implementing because the opencode-mcp server is absent
- Dispatch with a blocking wait tool, or resend a permission-denied call verbatim
- Start implementation on main/master without explicit user consent
- Skip the task review, or accept a review missing either verdict (spec
  compliance AND task quality)
- Run multiple OpenCode implementation sessions in parallel (conflicts)
- Carry one OpenCode session across tasks, or paste prior-task history into a
  dispatch
- Make the implementer read the whole plan (hand it `scripts/task-brief`
  output instead)
- Dispatch a reviewer without a diff file — generate it first
  (`scripts/review-package BASE HEAD`)
- Tell a reviewer what not to flag, or pre-rate a finding's severity
- Accept "close enough" on spec compliance, or move on with open
  Critical/Important findings
- Skip the re-review after fixes
- Accept "the tests pass" without having seen green output yourself
- Re-dispatch a task the ledger already marks complete — check the ledger
  (and `git log`) after any compaction or resume

## Integration

- **superpowers:writing-plans** — structure for the plan Phase 0 produces
- **superpowers:using-git-worktrees** — isolated workspace before execution
- **superpowers:requesting-code-review** — template for the final review
- **superpowers:finishing-a-development-branch** — after the final review is clean
- OpenCode should use TDD for each task (e.g. its `/test-driven-development`
  skill, if exposed)
