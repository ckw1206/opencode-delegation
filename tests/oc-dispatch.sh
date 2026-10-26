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
  # STUB_NO_AGENTLIST models the real flake: the config-dir agent is appended
  # last and an async config load can print the listing without it.
  [ -n "${STUB_NO_AGENT:-}${STUB_NO_AGENTLIST:-}" ] || [ ! -f "$OPENCODE_CONFIG_DIR/agents/implementer.md" ] || echo "implementer (primary)"
  echo "build (primary)"
  exit 0
fi
if [ "$1" = debug ]; then # `debug config`: the resolved config, per $STUB_CONFIG
  # STUB_FLAKY_CONFIG=N: the first N calls fail, as concurrent starts do.
  if [ -n "${STUB_FLAKY_CONFIG:-}" ]; then
    calls=$(( $(cat "$STUB_LOG.cfgcalls" 2>/dev/null || echo 0) + 1 ))
    echo "$calls" > "$STUB_LOG.cfgcalls"
    [ "$calls" -gt "$STUB_FLAKY_CONFIG" ] || { echo "Error: busy" >&2; exit 1; }
  fi
  cfg=${STUB_CONFIG:-'{}'}
  # opencode resolves the config dir's agents into the merged config it prints;
  # a config dir whose implementer does not resolve is what STUB_NO_AGENT and
  # STUB_NO_RESOLVE model.
  if [ -z "${STUB_NO_AGENT:-}${STUB_NO_RESOLVE:-}" ] && [ -f "$OPENCODE_CONFIG_DIR/agents/implementer.md" ] &&
    [ -z "$(jq -r '.agent.implementer // empty' <<< "$cfg")" ]; then
    cfg=$(jq -c '. + {agent:{implementer:{model:(.model // "custom/stub-model")}}}' <<< "$cfg")
  fi
  # A notice on stderr must not be mistaken for part of the config: the gate
  # parses stdout only, so stderr noise cannot turn a loadable agent into a refusal.
  [ -z "${STUB_STDERR:-}" ] || printf 'WARN  opencode: some notice\n' >&2
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
step='{"type":"step_finish","part":{"tokens":{"input":100,"output":10,"reasoning":5,"cache":{"read":50}}}}'
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
  noreport) # ends on prose, e.g. a tool call written out as text
    echo '{"type":"text","part":{"type":"text","text":"Planning."}}'
    echo '{"type":"text","part":{"type":"text","text":"Now I will call edit with {\"path\": \"a.py\"}"}}' ;;
  length) # cut off at the output limit: opencode exits 0 without an error event
    echo '{"type":"step_finish","part":{"reason":"tool-calls","tokens":{"input":100,"output":10}}}'
    echo '{"type":"step_finish","part":{"reason":"length","tokens":{"input":100,"output":120,"reasoning":8000}}}' ;;
esac
EOF
chmod +x "$tmp/bin/opencode"
export PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/stub.log"

cd "$tmp/repo"
git init -q -b main
git config user.email t@t && git config user.name t
git commit -q --allow-empty -m init
printf '## Global Constraints\nPORT=8080\n' > plan.md
for i in $(seq 1 16); do printf '## Task %s: t%s\ndo %s\n' "$i" "$i" "$i" >> plan.md; done

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
  [ "$(field usage.reasoning_tokens)" = 10 ] && [ "$(field usage.peak_output)" = 15 ] &&
  [ "$(field 'warnings | length')" = 0 ] && pass "usage totals from step_finish events" || die "usage: $out"
cfg=$(sed -n 's/^config_dir=//p' "$STUB_LOG")
[ -f "$cfg/agents/implementer.md" ] && grep -q -- '--agent implementer' "$STUB_LOG" &&
  pass "implementer agent dir passed via OPENCODE_CONFIG_DIR" || die "config dir: $cfg"
base2=$(field base) ev2=$(field events)
cp "$ev2" "$tmp/ev2"

run nocommit plan.md 3 wt3
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"no commits"* ]] && pass "DONE without commits -> ERROR" || die "nocommit: $out"

run noreport plan.md 4 wt4
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"no report"* ]] && [ "$(field error_kind)" = no_report ] &&
  [[ "$(field last_text)" == *'call edit with {"path"'* ]] && [ "$(field resumable)" = null ] &&
  pass "missing report -> ERROR no_report with the last text" || die "noreport: $out"

run badjson plan.md 5 wt5
[ "$rc" -eq 1 ] && [[ "$(field error)" == *"known status"* ]] && pass "non-JSON report -> ERROR" || die "badjson: $out"

run blocked plan.md 6 wt6
[ "$rc" -eq 0 ] && [ "$(field status)" = BLOCKED ] && [ "$(field commits)" = 0 ] && pass "BLOCKED passes through" || die "blocked: $out"

echo "fix the off-by-one at work.txt:1" > "$tmp/fix.md"
run done plan.md 2 wt2 ses_stub "$tmp/fix.md"
[ "$rc" -eq 0 ] && [ "$(field commits)" = 2 ] && [ "$(field base)" = "$base2" ] &&
  grep -q -- '--session ses_stub' "$STUB_LOG" && grep -q 'off-by-one' "$STUB_LOG" &&
  pass "follow-up turn reuses session, worktree and base" || die "follow-up: $out"
grep -q 'without stopping to ask for approval' "$STUB_LOG" && pass "follow-up asks for every item in one turn" ||
  die "follow-up footer"
[ "$(field events)" != "$ev2" ] && cmp -s "$ev2" "$tmp/ev2" && [ wt2/.sdd/task-2-events.jsonl -ef "$(field events)" ] &&
  [ -e wt2/.sdd/task-2-stderr.1.log ] && [ -e wt2/.sdd/task-2-stderr.2.log ] &&
  pass "follow-up turn logs to its own files; earlier turn's events kept" || die "follow-up events: $out"

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
[ "$rc" -eq 0 ] && [ "$(field 'warnings | length')" = 0 ] && [ "$(field usage.context_limit)" = 1000 ] &&
  [ "$(field usage.peak_ratio)" = 0.15 ] && pass "declared limit -> no warning, peak_ratio reported" || die "limit ok: $out"
STUB_CONFIG='{"model":"custom/m","provider":{"custom":{"models":{"m":{"limit":{"context":200,"output":100}}}}}}' \
  run done plan.md 9 wt9 ses_stub "$tmp/fix.md"
[ "$rc" -eq 0 ] && [ "$(field usage.peak_ratio)" = 0.75 ] && [[ "$(field 'warnings[0]')" == *"resume turn"* ]] &&
  pass "peak context past 70% of the window -> resume warning" || die "ratio warning: $out"

run overflow plan.md 10 wt10
[ "$rc" -eq 1 ] && [ "$(field status)" = ERROR ] && [ "$(field error_kind)" = context_overflow ] &&
  [ "$(field resumable)" = true ] && [ "$(field commits)" = 1 ] &&
  pass "context overflow -> ERROR context_overflow, resumable, commits kept" || die "overflow: $out"
base10=$(field base) ev10=$(field events)

echo "still open: the off-by-one at work.txt:1" > "$tmp/resume.md"
run done plan.md 10 wt10 --resume "$tmp/resume.md"
[ "$rc" -eq 0 ] && [ "$(field status)" = DONE ] && [ "$(field commits)" = 2 ] && [ "$(field base)" = "$base10" ] &&
  ! grep -q -- '--session' "$STUB_LOG" && grep -q 'RESUME' "$STUB_LOG" && grep -q "$base10" "$STUB_LOG" &&
  grep -q 'still open' "$STUB_LOG" && grep -q 'REPORT: ' "$STUB_LOG" &&
  pass "resume starts a fresh session on the same worktree and base" || die "resume: $out"
[ "$(field events)" != "$ev10" ] && grep -q ContextOverflowError "$ev10" &&
  [ wt10/.sdd/task-10-events.jsonl -ef "$(field events)" ] &&
  pass "resume turn logs to its own file; the overflowed turn's events kept" || die "resume events: $out"

grep -q 'one item at a time' "$STUB_LOG" && pass "resume asks for one item at a time" || die "resume item rule"

rm wt10/.sdd/task-10-events.jsonl && echo legacy > wt10/.sdd/task-10-events.jsonl # logged before turns were numbered
run length plan.md 10 wt10 --resume
[ "$rc" -eq 1 ] && [ "$(field error_kind)" = output_length ] && [ "$(field resumable)" = true ] &&
  [[ "$(field error)" == *"output limit"* ]] && pass "output-length stop without report -> output_length, resumable" ||
  die "length: $out"
[[ "$(field error)" != *"raise limit.output"* ]] && pass "no declared output limit -> no cap hint" || die "length hint: $out"
grep -q legacy wt10/.sdd/task-10-events.0.jsonl && [ wt10/.sdd/task-10-events.jsonl -ef "$(field events)" ] &&
  pass "un-numbered events file from before is kept" || die "legacy events: $(ls wt10/.sdd)"

run done plan.md 11 wt11 --resume 2>/dev/null
[ "$rc" -eq 2 ] && [ ! -e wt11 ] && pass "resume without a worktree -> exit 2" || die "resume no wt: rc=$rc"

rm -f "$STUB_LOG"
rc=0; STUB_NO_AGENT=1 STUB_MODE=done "$dispatch" plan.md 7 wt7 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && [ ! -e wt7 ] && [ ! -e "$STUB_LOG" ] &&
  pass "unloadable implementer agent -> refuse before opencode run" || die "no-agent: rc=$rc"

run done plan.md 99 wt99 2>/dev/null
[ "$rc" -ne 0 ] && [ ! -e wt99 ] && ! git show-ref --verify --quiet refs/heads/oc/task-99 &&
  pass "unknown task fails without leaving a worktree or branch" || die "task 99: rc=$rc"

# The listing flake: `opencode agent list` can print without the config-dir
# agent (it is appended last, after an async config load) even with a single
# process running. That is a false negative, not a missing agent, so dispatch
# must not refuse on it -- and it must still refuse when the agent genuinely
# does not resolve into the config opencode will run with.
rm -f "$STUB_LOG"
rc=0; STUB_NO_AGENTLIST=1 STUB_MODE=done "$dispatch" plan.md 11 wt-flaky >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ -d wt-flaky ] && grep -q -- '--agent implementer' "$STUB_LOG" &&
  pass "agent list missing the config-dir agent does not block dispatch" ||
  die "flaky agent list: rc=$rc"

# Fresh task number: 11 is already built by the test above, and reusing it would
# let the branch-exists check satisfy this assertion instead of the agent gate.
rc=0; STUB_NO_RESOLVE=1 STUB_MODE=done "$dispatch" plan.md 12 wt-noresolve >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && [ ! -e wt-noresolve ] &&
  pass "agent absent from the resolved config -> refuse before opencode run" ||
  die "no-resolve: rc=$rc"

# The gate must not refuse a legitimately configured user because opencode wrote a
# notice to stderr: `debug config` stdout is the config, stderr is not.
rc=0; STUB_STDERR=1 STUB_MODE=done "$dispatch" plan.md 13 wt-stderr >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ -d wt-stderr ] && grep -q -- '--agent implementer' "$STUB_LOG" &&
  pass "stderr noise does not corrupt the config probe" ||
  die "stderr banner: rc=$rc"

# Concurrent starts: `debug config` can fail transiently; dispatch retries it,
# and still refuses (exit 2, nothing created) when it never succeeds.
export OC_DISPATCH_RETRY_DELAY=0
rm -f "$STUB_LOG" "$STUB_LOG.cfgcalls"
rc=0; STUB_FLAKY_CONFIG=2 STUB_MODE=done "$dispatch" plan.md 14 wt-flakycfg >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && [ -d wt-flakycfg ] && pass "transient debug config failure is retried" ||
  die "flaky config: rc=$rc"
rm -f "$STUB_LOG.cfgcalls"
rc=0; STUB_FLAKY_CONFIG=99 STUB_MODE=done "$dispatch" plan.md 15 wt-deadcfg >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && [ ! -e wt-deadcfg ] && pass "persistent debug config failure -> exit 2" ||
  die "dead config: rc=$rc"

# Reasoning counts toward the output cap: a response whose reasoning reached
# the declared limit will reach it again on resume, so the error says so.
STUB_CONFIG='{"model":"custom/m","provider":{"custom":{"models":{"m":{"limit":{"context":100000,"output":8192}}}}}}' \
  run length plan.md 16 wt16
[ "$rc" -eq 1 ] && [ "$(field error_kind)" = output_length ] && [ "$(field usage.peak_output)" = 8120 ] &&
  [[ "$(field error)" == *"8120 of the model's declared limit.output 8192"* ]] &&
  pass "output_length at the declared cap -> raise-limit hint" || die "cap hint: $out"
