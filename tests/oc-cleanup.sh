#!/usr/bin/env bash
# Self-check for scripts/oc-cleanup.
# Usage: tests/oc-cleanup.sh   (prints "ok" lines; exits non-zero on failure)
set -euo pipefail

cleanup=$(cd "$(dirname "$0")/.." && pwd)/scripts/oc-cleanup
tmp=$(mktemp -d)
trap 'kill "${fake:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

pass() { echo "ok - $1"; }
die() { echo "FAIL - $1" >&2; exit 1; }
has_branch() { git show-ref --verify --quiet "refs/heads/$1"; }

cd "$tmp" && git init -q -b main repo && cd repo
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init

task() { # $1 = N, $2 = merge|keep|fresh: a task branch in a worktree; fresh = no commit, no report yet
  git worktree add -q -b "oc/task-$1" "wt$1" HEAD
  mkdir -p "wt$1/.sdd" && printf '*\n' > "wt$1/.sdd/.gitignore" && echo log > "wt$1/.sdd/events.jsonl"
  [ "$2" != fresh ] || return 0
  echo '{"status":"DONE"}' > "wt$1/.sdd/task-$1-report.json"
  echo "$1" > "wt$1/f$1.txt" && git -C "wt$1" add "f$1.txt" && git -C "wt$1" commit -qm "task $1"
  [ "$2" = keep ] || git merge -q --no-ff --no-edit "oc/task-$1"
}
task 1 merge                                   # merged, clean worktree (ignored .sdd only)
task 2 merge && git worktree remove wt2        # merged, no worktree
task 3 keep                                    # not merged
task 4 merge && echo dirty >> wt4/f4.txt       # merged, uncommitted change
git branch feature/other                       # not a task branch
task 5 fresh                                   # dispatched, nothing committed or reported yet
task 6 fresh && echo '{"status":"BLOCKED"}' > wt6/.sdd/task-6-report.json  # reported, and
# a follow-up turn is running: a fake opencode whose argv carries --dir like the real one
cat > "$tmp/opencode" <<'EOF'
#!/bin/sh
trap 'kill $!; exit' TERM
sleep 60 & wait
EOF
chmod +x "$tmp/opencode"
"$tmp/opencode" run --agent implementer --dir "$(cd wt6 && pwd -P)" --session s </dev/null >/dev/null 2>&1 & fake=$!

out=$("$cleanup" -n 2>&1) || die "oc-cleanup -n exited non-zero: $out"
has_branch oc/task-1 && [ -d wt1 ] && [[ "$out" == *"would remove: oc/task-1 (worktree"* ]] &&
  [[ "$out" == *"not merged, kept: oc/task-3"* ]] && pass "dry run lists and changes nothing" || die "dry run: $out"
[[ "$out" == *"kept: oc/task-5 (worktree"*"no report yet"* ]] && [[ "$out" != *"would remove: oc/task-5"* ]] &&
  pass "dry run keeps a zero-commit task with no report" || die "dry run task 5: $out"
[[ "$out" == *"kept: oc/task-6 (worktree"*"running opencode"* ]] && [[ "$out" != *"would remove: oc/task-6"* ]] &&
  pass "dry run keeps a worktree with a running opencode" || die "dry run task 6: $out"

out=$("$cleanup" 2>&1) || die "oc-cleanup exited non-zero: $out"
! has_branch oc/task-1 && [ ! -d wt1 ] && pass "merged task with clean worktree removed" || die "task 1: $out"
! has_branch oc/task-2 && pass "merged task without worktree removed" || die "task 2: $out"
has_branch oc/task-3 && [ -d wt3 ] && pass "unmerged task kept" || die "task 3: $out"
has_branch oc/task-4 && [ -d wt4 ] && [[ "$out" == *"kept: oc/task-4 (worktree"*"uncommitted"* ]] &&
  pass "merged task with uncommitted changes kept and reported" || die "task 4: $out"
has_branch feature/other && pass "non-task branches untouched" || die "feature/other"
has_branch oc/task-5 && [ -d wt5 ] && has_branch oc/task-6 && [ -d wt6 ] &&
  pass "in-flight tasks kept" || die "tasks 5/6: $out"
[[ "$out" == *"removed 2 merged task branch(es); kept 4"* ]] && pass "summary counts" || die "summary: $out"

rc=0; "$cleanup" -x >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "unknown option exits 2" || die "bad option exit $rc"
