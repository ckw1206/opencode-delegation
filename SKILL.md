---
name: opencode-delegation
description: >-
  Use when the user wants OpenCode to do the hands-on coding — building a
  feature, fixing a bug, refactoring, writing a script, or any multi-step
  implementation task. Triggers include "have OpenCode build this", "delegate
  this to OpenCode", "use OpenCode to implement", or OpenCode delegation being
  the established working mode for the project. Use even when the user names
  only the implementation, not the review process.
---

# OpenCode Development Delegation

Execute a plan by dispatching a fresh OpenCode session per task — independent
tasks in parallel — a task review
(spec compliance + code quality) by a reviewer subagent after each, and
a broad whole-branch review at the end.

Paths like `scripts/task-brief` are relative to this skill's directory (the one
containing this `SKILL.md`), not the user's repo — resolve that directory before
running them.

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
- **A reviewer subagent reviews** each task's diff — a separate session from
  the implementer, dispatched fresh per review with no sunk cost in the code.
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

## Dispatching with oc-dispatch

OpenCode runs headless through `scripts/oc-dispatch`, one task per call, as
the restricted `implementer` agent shipped in `.opencode/agents/` (no pushes,
no cluster, SSH or container-runtime access, no `.env` reads, no printing its
environment). It cannot ask questions
interactively; it reports NEEDS_CONTEXT instead. Run it from the user's repo
root, on the working branch:

```bash
SKILL=/path/to/this/skill   # the directory containing this SKILL.md
wt="$("$SKILL/scripts/sdd-workspace")/wt/task-N"
"$SKILL/scripts/oc-dispatch" PLAN_FILE N "$wt"                      # first turn
"$SKILL/scripts/oc-dispatch" PLAN_FILE N "$wt" SESSION_ID MSG_FILE  # follow-up
"$SKILL/scripts/oc-dispatch" PLAN_FILE N "$wt" --resume [MSG_FILE]  # resume
```

The first turn creates the worktree on a new branch `oc/task-N` from HEAD and
hands OpenCode the task's brief — its plan section plus the Global Constraints
— and nothing else. A follow-up turn sends MSG_FILE (your answers, or review
findings) into the same session; the task's base commit is kept. A resume turn
starts a **new** session on the same worktree, branch and base: the implementer
re-reads the brief, picks up from the task's commits, and gets MSG_FILE for
whatever is still outstanding.

Each call prints one JSON line: the implementer's report (`status`, `summary`,
`files_changed`, `tests`, `guards`, `concerns`, `questions`) plus `session`,
`base`, `head`, `commits`, `worktree`, `brief`, `report`, `events`, `usage`
(`steps`, `input_tokens`, `output_tokens`, `peak_context`, `duration_s` for
this turn) and `warnings`. Exit 0 = a real status; exit 1 = `status: ERROR`
with the cause in `.error` and its class in `.error_kind`; exit 2 = usage or
setup error.

- **Read `warnings` on the first dispatch.** A warning that the model declares
  no limit means OpenCode can't compact before its context window overflows:
  tell the user once (the fix is a `limit` on that model in their OpenCode
  provider config, see the README), then carry on.

- **It blocks until OpenCode finishes — often minutes.** Run it as a background
  command if your harness has one and tell the user the task is running;
  otherwise give it the longest timeout available.
- **Exit 2 with "opencode is not on PATH" or "jq is required":** stop and tell
  the user what to install (the README lists the requirements). Don't install
  it yourself, and don't fall back to implementing — that defeats the whole
  purpose.
- **ERROR with `error_kind` `context_overflow` or `output_length`**
  (`resumable: true`): the session ran out of room, and its commits are still
  on the branch. Run a resume turn. Never send a follow-up into that session,
  and never discard the worktree and start over, which throws the committed
  work away. If the same task overflows twice, it is too big: split it.
- **Any other ERROR:** read `.error` (and the `events` file) before anything
  else. If it points at the provider or model, the user fixes that (`opencode
  providers login`) before you retry. Retry through a follow-up turn when
  `.session` is set; otherwise `git worktree remove --force "$wt" && git
  branch -D oc/task-N` and dispatch fresh. Never retry without changing
  something.
- **Credentials for tests** (a test database password, a service token) go in
  the environment of the `oc-dispatch` call itself, exported from wherever
  the project keeps them (e.g. `set -a; . ./.env; set +a` in the same
  command), never into a brief or a message file. Task worktrees don't have
  the project's ignored env files, the implementer agent can't read them, and
  it is told never to print its environment.
- **If a dispatch is denied at the permission prompt**, do not resend the
  identical call. Say once what needs approving, then wait for the user's
  go-ahead.

**Session lifecycle:** one fresh OpenCode session per task. A task's session is
reused for exactly two things — answering that task's NEEDS_CONTEXT questions,
and fix rounds after its review — and is abandoned when the task is marked
complete. The next task starts a new session with its own brief and the code
in its worktree — never the accumulated history of prior tasks. When a turn's
`usage.peak_context` is past about three quarters of the model's context
window, run the next fix round as a resume turn instead of a follow-up: a
follow-up into a nearly full session is how fix rounds overflow.

Every follow-up message is a briefing to a capable colleague who can't see your
screen: specific, with file:line, why, and what good looks like. Exact values
live in the brief file, not the message.

## Phase 0 — Get a sound plan

If a written implementation plan already exists for this work, skip to
Pre-flight. Otherwise write one yourself — with your agent's planning skill if
it has one — covering problem analysis, requirements, approach, risks and
assumptions, test strategy, and step-by-step tasks. A plan is not
implementation code; writing it is the controller's job.

**Format requirements** (the execution machinery depends on them): the plan is
a markdown file; each task under a `## Task N: <name>` heading containing its
complete requirements; binding cross-task requirements (exact values, formats,
"same layout as X" relationships) in a `## Global Constraints` section.
Each task also states `Depends on:` (the task numbers it needs merged first,
or `none`) and `Files:` (what it creates or changes), and `Shares:` when its
tests use something other tasks' tests also use (a test database, a fixed
port, a fixture directory), or `none`. Cut the work so most tasks depend on
nothing and touch different files — independent tasks run in parallel, and a
plan that is one long chain gives that up.

Size each task for the implementer model, not for yourself: one module, one
route group or one screen, which a single session can finish without filling
its context window. A task that needs many fix rounds, or overflows twice, was
too big; split the rest of the plan finer. Put the model's working limits in
the plan's Global Constraints only if they differ from what the shipped
implementer agent already says.

Then **pressure-test it as the senior engineer in the room.** Read it against
the actual codebase — open the files it proposes to touch, check that its
assumptions about existing structure hold. Hunt for:

- Weak or unstated assumptions ("assumes the API returns sorted results" — does it?)
- Missing edge cases and failure modes
- Requirements the user implied but the plan dropped
- Architectural choices that will age badly or fight existing patterns
- A test strategy that wouldn't actually catch the bugs that matter here

Revise until the plan is genuinely sound — a few rounds here is cheaper than
discovering a design hole after the code is written. Then show the user the
plan and get their go-ahead before Task 1: a plan you wrote yourself needs a
second pair of eyes.

## Pre-flight plan review

Before dispatching Task 1, scan the plan once for conflicts: tasks that
contradict each other or the Global Constraints, and anything the plan
explicitly mandates that the review rubric treats as a defect (a test that
asserts nothing, verbatim duplication of a logic block), and task sections
that lean on context they don't contain — the implementer's first turn sees
only its own section, the Global Constraints, and the code. Present everything
you find to the user as one batched question — each finding beside the plan
text that mandates it, asking which governs. If the scan is clean, proceed
without comment.

Also confirm you're on a working branch — never start implementation on
main/master without explicit user consent.

## Execution in waves

Run the plan in waves of parallel tasks. A wave is every incomplete task whose
dependencies are all merged and whose `Files:` and `Shares:` overlap no other
task in the wave, capped at 4 (cost and provider rate limits). Two tasks whose
tests share a database or a port can each pass alone and fail together, so a
shared resource serializes them just like a shared file. Dispatch the whole wave at
once — one `oc-dispatch` per task, each as its own background command — and
take each task through the loop below **as soon as its dispatch returns**:
don't hold the fastest task's review for the slowest task. Reviewer subagents
run in parallel too. Start the next wave when every task in this one is
merged, after `scripts/oc-cleanup` has removed the wave's merged worktrees and
branches (it never touches unmerged ones; `-n` lists without removing). A
strict chain of tasks simply runs one per wave.

For each task:

1. **Dispatch** the task's first turn with `oc-dispatch` (see above). The
   brief it extracts is the single source of requirements; never paste task
   text into a follow-up. The result's `base` and `head` are the review range
   — never `HEAD~1`, which silently drops all but the last commit of a
   multi-commit task.
2. **Handle the status**:
   - **DONE** → proceed to review.
   - **DONE_WITH_CONCERNS** → read `concerns`. Correctness or scope concerns
     get addressed before review; observations get noted and you proceed.
   - **NEEDS_CONTEXT** → write answers to its `questions` into a message file
     (e.g. `.sdd/task-N-msg.md`) and run a follow-up turn; it continues.
   - **BLOCKED** → if it's a context problem, provide more context in a
     follow-up turn. If the task is too large, split it into smaller pieces
     and dispatch each. If the plan itself is wrong, escalate to the user.
     Never ignore an escalation or push the implementer to retry without
     changing something.
   - **ERROR** → see the ERROR rule above.
3. **Review**: run `scripts/review-package BASE HEAD` with the result's `base`
   and `head` (prints the diff-file path; the package never enters your
   context), then dispatch a reviewer subagent per
   [task-reviewer-prompt.md](task-reviewer-prompt.md) with the result's
   `brief` and `report` paths, the package path, and the Global Constraints
   copied verbatim. When filling the template: no open-ended directives
   ("check all uses") without a concrete task-specific reason, no re-running
   tests the implementer already ran, and no pre-judging findings — if your
   prompt contains "do not flag" or "at most Minor", stop: let the reviewer
   raise it and adjudicate in the loop.
4. **Check what a diff review can't**, while the reviewer works:
   - **Run it.** When the task changes something a person uses (a page, a
     CLI command, an API response), exercise it in the running software
     from the task's worktree: drive web UIs through your harness's browser
     tool if it has one, run the CLI, call the endpoint. Check the console
     or logs for errors. Layout, copy, focus and state bugs pass unit tests
     and diff review alike, and only show up here.
   - **Prove the guards.** The report's `guards` lists each safeguard with
     the test that fails without it. A safeguard the diff adds but `guards`
     omits is a finding. For the risky ones (concurrency, authorization,
     anything that loses data), check the claim yourself in a throwaway
     worktree at the task's head: disable the safeguard, run its test,
     expect a failure, then remove the throwaway worktree. That is
     inspection, not implementation: the edit is never committed. A test
     that still passes is an Important finding.

   What you find goes into the same fix round as the reviewer's findings.
5. **Act on the verdicts**:
   - Critical/Important findings → write them to a message file as specific,
     actionable feedback (file:line, why it's a problem, what good looks
     like) and run a follow-up turn, or a resume turn when the session is
     nearly full (see Session lifecycle). OpenCode fixes, re-runs the covering
     tests, and rewrites its report. Confirm the new report names the
     covering tests, the command run, and the output; then regenerate the
     review package for the full `base..head` range (the follow-up's result
     keeps the task's `base`) and re-review. Repeat until approved — never
     skip the re-review.
   - Minor findings → record in the progress ledger for final-review triage.
     A roll-up nobody reads is a silent discard.
   - ⚠️ "Cannot verify from diff" items → resolve each yourself before
     marking the task complete; you hold the plan and cross-task context the
     reviewer lacks. A confirmed gap is a failed spec review — back to
     OpenCode, then re-review.
   - A finding labeled plan-mandated — or any finding that conflicts with the
     plan's text — is the user's decision: present the finding and the plan
     text, ask which governs.
6. **Merge**, one task at a time even when tasks ran in parallel: from the
   repo root on the working branch, `git merge --ff-only oc/task-N`, or
   `git merge --no-ff --no-edit oc/task-N` when a wave-mate merged first.
   Then `git worktree remove "$wt"` and `git branch -d oc/task-N`. On a
   conflict, `git merge --abort`, remove the worktree, `git branch -D
   oc/task-N`, correct the plan's `Files:` lines, and re-dispatch the task
   fresh on top of the new HEAD. The next wave's worktrees branch from HEAD,
   so HEAD must have every merged task's commits.
7. **Mark complete**: append to the ledger (see Durable progress) and update
   your todo list. Next task.

## Final whole-branch review

After all tasks: run `scripts/review-package MERGE_BASE HEAD` (MERGE_BASE =
`git merge-base <base-branch> HEAD` or the branch's start commit) and dispatch a
reviewer subagent on the most capable available model, using
[task-reviewer-prompt.md](task-reviewer-prompt.md) adapted to branch scope —
the full plan file in place of a single task brief, the package path, and the
ledger's accumulated Minor findings so it can triage which must be fixed
before merge.

If it returns findings, fix them in **one** OpenCode session — not one fixer
per finding: write `final-fixes.md` in the `.sdd` workspace with the plan's
`## Global Constraints` section and a `## Task F: Final review fixes` section
listing every finding, dispatch it as task `F`, merge it like any task, then
re-review. When clean, finish the branch with the user: merge to the base
branch, open a pull request, or keep the branch — then run
`scripts/oc-cleanup`, settle any unmerged task branch it lists with the user,
and clean up the `.sdd` workspace.

## Durable progress

Conversation memory does not survive compaction; a controller that loses its
place re-dispatches completed work — the most expensive failure there is.
Track progress in a ledger file, not only in todos.

- At skill start, check
  `"$(git rev-parse --show-toplevel)/.sdd/progress-<plan-file-basename>.md"`
  (one ledger per plan, so another plan's run in the same repo can't mark your
  tasks complete). Tasks
  listed there as complete are DONE — resume at the first task not marked
  complete.
- When a task's review comes back clean, append:
  `Task N: complete (commits <base7>..<head7>, review clean)`.
- When a task needs a resume turn, append `Task N: resumed (<error_kind>)`,
  so a task that keeps overflowing shows up before it costs another round.
- After compaction, trust the ledger and `git log` over your own recollection.
- `git clean -fdx` destroys the ledger (it's git-ignored scratch); recover
  from `git log`.

## Final acceptance

Before telling the user it's complete, verify with evidence, not assumption:
the implementation matches the approved plan; the full test suite passes (you
ran it and saw it pass); the user-facing flows work end to end in the running
software (you exercised them, and the project's end-to-end suite passes if it
has one); no unaddressed findings remain. Then summarize:

- **What was implemented** — the change in plain terms.
- **Tests added or updated** — what now protects this behavior.
- **Key design decisions** — the choices worth knowing, and why.
- **Remaining risks** — anything you're watching, or "none" if you mean it.

## Red flags

**Never:**

- Implement or patch code yourself — even when it would be faster
- Fall back to implementing, or install OpenCode or jq yourself, because
  `oc-dispatch` can't run — tell the user what's missing
- Resend a permission-denied call verbatim, or retry an ERROR without
  changing anything
- Start implementation on main/master without explicit user consent
- Skip the task review, or accept a review missing either verdict (spec
  compliance AND task quality)
- Put tasks in the same wave that depend on each other, share files or share
  a test resource, or exceed 4 concurrent dispatches
- Carry one OpenCode session across tasks, or paste prior-task history into a
  dispatch
- Paste task text or the whole plan into a follow-up message (the brief
  already has the task)
- Start the next wave before every task in the current one is merged — its
  worktrees would start without that work
- Run a plan of independent tasks one at a time — waves exist so they don't
  wait on each other
- Dispatch a reviewer without a diff file — generate it first
  (`scripts/review-package BASE HEAD`)
- Tell a reviewer what not to flag, or pre-rate a finding's severity
- Accept "close enough" on spec compliance, or move on with open
  Critical/Important findings
- Skip the re-review after fixes
- Accept "the tests pass" without having seen green output yourself
- Accept a safeguard whose test still passes with the safeguard removed
- Call a user-facing task done without exercising it in the running software
- Send a follow-up into a session that overflowed, or discard an overflowed
  task's worktree — resume it
- Write credentials into a brief or a message file
- Re-dispatch a task the ledger already marks complete — check the ledger
  (and `git log`) after any compaction or resume

## Integration

- Run the execution on a working branch, never main/master; `oc-dispatch`
  gives each task its own worktree off it.
- If your agent has a planning skill, have it structure the plan Phase 0
  produces; the format requirements above are what the machinery needs.
- If your agent has its own code-review skill, its reviewer template can stand
  in for [task-reviewer-prompt.md](task-reviewer-prompt.md) — the same two
  verdicts apply (spec compliance AND code quality).
- OpenCode should use TDD for each task (e.g. its `/test-driven-development`
  skill, if exposed)
- If your harness has a browser tool, use it for the run-it check on web UIs;
  otherwise drive the software through its CLI or API, and tell the user what
  you couldn't exercise.
