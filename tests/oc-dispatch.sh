#!/usr/bin/env bash
# Self-check for scripts/oc-dispatch against a stub `opencode` on PATH.
# Usage: tests/oc-dispatch.sh   (prints "ok" lines; exits non-zero on failure)
set -euo pipefail

dispatch=$(cd "$(dirname "$0")/.." && pwd)/scripts/oc-dispatch
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin" "$tmp/repo"
cat > "$tmp/bin/opencode" <<'EOF'
#!/usr/bin/env bash
# Stub: behaves per $STUB_MODE; logs its args and config dir to $STUB_LOG.
if [ "$1" = agent ]; then
  [ -n "${STUB_NO_AGENT:-}" ] || [ ! -f "$OPENCODE_CONFIG_DIR/agents/implementer.md" ] || echo "implementer (primary)"
  echo "build (primary)"
  exit 0
fi
if [ "$1" = debug ]; then # `debug config`: the resolved config, per $STUB_CONFIG
  cfg=${STUB_CONFIG:-'{}'}
  echo "$cfg"
  exit 0
fi
dir= sid=
printf 'config_dir=%s\nargs=%s\n' "$OPENCODE_CONFIG_DIR" "$*" > "$STUB_LOG"
while [ $# -gt 1 ]; do
  case $1 in --dir) dir=$2; shift ;; --session) sid=$2; shift ;; esac
  shift
done
report=$(printf '%s' "$1" | sed -n 's/.*REPORT: \([^ ]*\).*/\1/p' | tail -1)
if [ "$STUB_MODE" = error ]; then
  echo '{"type":"error","sessionID":"ses_err","error":{"name":"APIError","data":{"message":"Cannot connect to API"}}}'
  exit 1
fi
echo "{\"type\":\"step_start\",\"sessionID\":\"${sid:-ses_stub}\"}"
step='{"type":"step_finish","part":{"tokens":{"input":100,"output":10,"cache":{"read":50}}}}'
case $STUB_MODE in
  done)
    echo "$RANDOM" >> "$dir/work.txt"
    git -C "$dir" add work.txt && git -C "$dir" commit -qm "stub work"
    echo "$step"; echo "$step"
    echo '{"status":"DONE","summary":"stub","concerns":[]}' > "$report" ;;
  overflow)
    echo "$RANDOM" >> "$dir/work.txt"
    git -C "$dir" add work.txt && git -C "$dir" commit -qm "stub partial work"
    echo '{"type":"error","error":{"name":"ContextOverflowError","data":{"message":"Requested token count exceeds the maximum context length"}}}' ;;
  nocommit) echo '{"status":"DONE"}' > "$report" ;;
  blocked) echo '{"status":"BLOCKED","concerns":["stuck"]}' > "$report" ;;
  badjson) echo 'not json' > "$report" ;;
  noreport) ;;
esac
EOF
chmod +x "$tmp/bin/opencode"
export PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/stub.log"

cd "$tmp/repo"
git init -q -b main
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init
printf '## Global Constraints\nPORT=8080\n' > plan.md
for i in 1 2 3 4 5 6 7 8 9 10 11; do printf '## Task %s: t%s\ndo %s\n' "$i" "$i" "$i" >> plan.md; done

pass() { echo "ok - $1"; }
die() { echo "FAIL - $1" >&2; exit 1; }
run() { # run MODE ARGS... -> sets $out and $rc
  rc=0
  out=$(STUB_MODE=$1 "$dispatch" "${@:2}") || rc=$?
}
field() { jq -r ".$1" <<< "$out"; }

rc=0; "$dispatch" plan.md 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] && pass "usage error exits 2" || die "usage exit $rc"

run error plan.md 1 wt1
[ "$rc" -eq 1 ] && [ "$(field status)" = ERROR ] && [ "$(field session)" = ses_err ] &&
  [[ "$(field error)" == *"Cannot connect to API"* ]] && pass "error event -> ERROR with message + session" ||
  die "error mode: rc=$rc $out"

run done plan.md 2 wt2
[ "$rc" -eq 0 ] && [ "$(field status)" = DONE ] && [ "$(field commits)" = 1 ] &&
  [ "$(field branch)" = oc/task-2 ] && [ "$(field session)" = ses_stub ] && [ "$(field dirty)" = false ] &&
  pass "DONE with commit" || die "done mode: rc=$rc $out"
grep -q 'PORT=8080' "$(field brief)" && grep -q '^## Task 2' "$(field brief)" &&
  pass "brief has task + Global Constraints" || die "brief content"
[ "$(field usage.steps)" = 2 ] && [ "$(field usage.input_tokens)" = 200 ] &&
  [ "$(field usage.output_tokens)" = 20 ] && [ "$(field usage.peak_context)" = 150 ] &&
  [ "$(field 'warnings | length')" = 0 ] && pass "usage totals from step_finish events" || die "usage: $out"
cfg=$(sed -n 's/^config_dir=//p' "$STUB_LOG")
[ -f "$cfg/agents/implementer.md" ] && grep -q -- '--agent implementer' "$STUB_LOG" &&
  pass "implementer agent dir passed via OPENCODE_CONFIG_DIR" || die "config dir: $cfg"
base2=$(field base)

run nocommit plan.md 3 wt3
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"no commits"* ]] && pass "DONE without commits -> ERROR" || die "nocommit: $out"

run noreport plan.md 4 wt4
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"no report"* ]] && pass "missing report -> ERROR" || die "noreport: $out"

run badjson plan.md 5 wt5
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"known status"* ]] && pass "non-JSON report -> ERROR" || die "badjson: $out"

run blocked plan.md 6 wt6
[ "$rc" -eq 0 ] && [ "$(field status)" = BLOCKED ] && [ "$(field commits)" = 0 ] && pass "BLOCKED passes through" || die "blocked: $out"

echo "fix the off-by-one at work.txt:1" > "$tmp/fix.md"
run done plan.md 2 wt2 ses_stub "$tmp/fix.md"
[ "$rc" -eq 0 ] && [ "$(field commits)" = 2 ] && [ "$(field base)" = "$base2" ] &&
  grep -q -- '--session ses_stub' "$STUB_LOG" && grep -q 'off-by-one' "$STUB_LOG" &&
  pass "follow-up turn reuses session, worktree and base" || die "follow-up: $out"

run noreport plan.md 2 wt2 ses_stub "$tmp/fix.md"
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"no report"* ]] && pass "stale report never reused" || die "stale: $out"

rc=0; STUB_MODE=done "$dispatch" plan.md 2 wt2 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "first turn refuses existing worktree" || die "existing worktree exit $rc"

rc=0; "$dispatch" plan.md 2 wt2 ses_stub >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "four arguments without --resume -> usage error" || die "4 args exit $rc"

STUB_CONFIG='{"model":"custom/m","provider":{"custom":{"models":{"m":{}}}}}' run done plan.md 8 wt8
[ "$rc" -eq 0 ] && [ "$(field 'warnings | length')" = 1 ] && [[ "$(field 'warnings[0]')" == *custom/m* ]] &&
  pass "custom model without a limit -> warning" || die "limit warning: $out"
STUB_CONFIG='{"model":"custom/m","provider":{"custom":{"models":{"m":{"limit":{"context":1000,"output":100}}}}}}' \
  run done plan.md 9 wt9
[ "$rc" -eq 0 ] && [ "$(field 'warnings | length')" = 0 ] && pass "declared limit -> no warning" || die "limit ok: $out"

run overflow plan.md 10 wt10
[ "$rc" -eq 1 ] && [ "$(field status)" = ERROR ] && [ "$(field error_kind)" = context_overflow ] &&
  [ "$(field resumable)" = true ] && [ "$(field commits)" = 1 ] &&
  pass "context overflow -> ERROR context_overflow, resumable, commits kept" || die "overflow: $out"
base10=$(field base)

echo "still open: the off-by-one at work.txt:1" > "$tmp/resume.md"
run done plan.md 10 wt10 --resume "$tmp/resume.md"
[ "$rc" -eq 0 ] && [ "$(field status)" = DONE ] && [ "$(field commits)" = 2 ] && [ "$(field base)" = "$base10" ] &&
  ! grep -q -- '--session' "$STUB_LOG" && grep -q 'RESUME' "$STUB_LOG" && grep -q "$base10" "$STUB_LOG" &&
  grep -q 'still open' "$STUB_LOG" && grep -q 'REPORT: ' "$STUB_LOG" &&
  pass "resume starts a fresh session on the same worktree and base" || die "resume: $out"

run done plan.md 11 wt11 --resume 2>/dev/null
[ "$rc" -eq 2 ] && [ ! -e wt11 ] && pass "resume without a worktree -> exit 2" || die "resume no wt: rc=$rc"

rm -f "$STUB_LOG"
rc=0; STUB_NO_AGENT=1 STUB_MODE=done "$dispatch" plan.md 7 wt7 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && [ ! -e wt7 ] && [ ! -e "$STUB_LOG" ] &&
  pass "unloadable implementer agent -> refuse before opencode run" || die "no-agent: rc=$rc"

run done plan.md 99 wt99 2>/dev/null
[ "$rc" -ne 0 ] && [ ! -e wt99 ] && ! git show-ref --verify --quiet refs/heads/oc/task-99 &&
  pass "unknown task fails without leaving a worktree or branch" || die "task 99: rc=$rc"
