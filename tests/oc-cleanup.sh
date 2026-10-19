#!/usr/bin/env bash
# Self-check for scripts/oc-cleanup.
# Usage: tests/oc-cleanup.sh   (prints "ok" lines; exits non-zero on failure)
set -euo pipefail

cleanup=$(cd "$(dirname "$0")/.." && pwd)/scripts/oc-cleanup
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok - $1"; }
die() { echo "FAIL - $1" >&2; exit 1; }
has_branch() { git show-ref --verify --quiet "refs/heads/$1"; }

cd "$tmp" && git init -q -b main repo && cd repo
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init

task() { # $1 = N, $2 = merge|keep: a task branch with one commit in a worktree
  git worktree add -q -b "oc/task-$1" "wt$1" HEAD
  mkdir -p "wt$1/.sdd" && printf '*\n' > "wt$1/.sdd/.gitignore" && echo log > "wt$1/.sdd/events.jsonl"
  echo "$1" > "wt$1/f$1.txt" && git -C "wt$1" add "f$1.txt" && git -C "wt$1" commit -qm "task $1"
  [ "$2" = keep ] || git merge -q --no-ff --no-edit "oc/task-$1"
}
task 1 merge                                   # merged, clean worktree (ignored .sdd only)
task 2 merge && git worktree remove wt2        # merged, no worktree
task 3 keep                                    # not merged
task 4 merge && echo dirty >> wt4/f4.txt       # merged, uncommitted change
git branch feature/other                       # not a task branch

out=$("$cleanup" -n 2>&1) || die "oc-cleanup -n exited non-zero: $out"
has_branch oc/task-1 && [ -d wt1 ] && [[ "$out" == *"would remove: oc/task-1 (worktree"* ]] &&
  [[ "$out" == *"not merged, kept: oc/task-3"* ]] && pass "dry run lists and changes nothing" || die "dry run: $out"

out=$("$cleanup" 2>&1) || die "oc-cleanup exited non-zero: $out"
! has_branch oc/task-1 && [ ! -d wt1 ] && pass "merged task with clean worktree removed" || die "task 1: $out"
! has_branch oc/task-2 && pass "merged task without worktree removed" || die "task 2: $out"
has_branch oc/task-3 && [ -d wt3 ] && pass "unmerged task kept" || die "task 3: $out"
has_branch oc/task-4 && [ -d wt4 ] && [[ "$out" == *"kept: oc/task-4 (worktree"*"uncommitted"* ]] &&
  pass "merged task with uncommitted changes kept and reported" || die "task 4: $out"
has_branch feature/other && pass "non-task branches untouched" || die "feature/other"
[[ "$out" == *"removed 2 merged task branch(es); kept 2"* ]] && pass "summary counts" || die "summary: $out"

rc=0; "$cleanup" -x >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "unknown option exits 2" || die "bad option exit $rc"
