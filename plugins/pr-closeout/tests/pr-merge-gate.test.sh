#!/bin/bash
# Tests for plugins/pr-closeout/hooks/pr-merge-gate.sh (PreToolUse, Bash and GitHub MCP merge).
# Usage: bash plugins/pr-closeout/tests/pr-merge-gate.test.sh   (HOOK=<path> to test a copy)
# A fake `ready` (PR_CLOSEOUT_SCRIPT) answers with FAKE_RC and records the arguments it got, so the
# cases check both the decision and what the hook asked. Mutants at the end must die on their case.
set -u
here=$(cd "$(dirname "$0")" && pwd)
HOOK=${HOOK:-"$here/../hooks/pr-merge-gate.sh"}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmg-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
command -v jq >/dev/null 2>&1 || { echo "pr-merge-gate.test: jq is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "pr-merge-gate.test: node is required"; exit 1; }

cat > "$tmp/fake-ready.mjs" <<'JS'
import fs from 'node:fs';
fs.appendFileSync(process.env.FAKE_LOG, process.argv.slice(2).join(' ') + '\n');
const rc = Number(process.env.FAKE_RC || 0);
const gate = process.env.FAKE_GATE || null;
process.stdout.write(JSON.stringify({ exit: rc, gate, hits: rc ? [{ code: 'x', gate, detail: 'fake detail' }] : [] }));
process.exitCode = rc;
JS
export PR_CLOSEOUT_SCRIPT="$tmp/fake-ready.mjs" FAKE_LOG="$tmp/calls"

pass=0; fail=0
failed() { fail=$((fail + 1)); echo "FAIL $1"; [ "${STOP_ON_FAIL:-0}" = 1 ] && exit 1; return 0; }
ok() { pass=$((pass + 1)); }
# gate <want allow|deny> <label> <hook stdin json>; leaves stdout in $tmp/out, calls in $tmp/calls
gate() {
  local want=$1 label=$2 json=$3 rc got
  rm -f "$tmp/calls"
  printf '%s' "$json" | bash "$HOOK" > "$tmp/out" 2> "$tmp/err"; rc=$?
  got=allow; jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$tmp/out" >/dev/null 2>&1 && got=deny
  if [ "$rc" = 0 ] && [ "$got" = "$want" ]; then ok; else failed "[$label] decision $got rc=$rc, expected $want: $(head -c 200 "$tmp/out")"; fi
}
bash_in() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
mcp_in() { jq -cn --argjson i "$1" '{hook_event_name:"PreToolUse",tool_name:"mcp__claude_ai_GitHub_MCP_Server__merge_pull_request",tool_input:$i}'; }
called() { local want=$1 label=$2 got; got=$(cat "$tmp/calls" 2>/dev/null); if [ "$got" = "$want" ]; then ok; else failed "[$label] ready called with [$got], expected [$want]"; fi; }
reason_has() { if jq -r '.hookSpecificOutput.permissionDecisionReason // ""' "$tmp/out" | command grep -qF -- "$2"; then ok; else failed "[$1] reason lacks: $2"; fi; }
SHA=1111111111111111111111111111111111111111

# ── parsing: which PR, which repo, which head ────────────────────────────────────────────────────
FAKE_RC=0 gate allow "gh pr merge, --repo" "$(bash_in 'gh pr merge 3 --repo o/r --squash')"
called "ready o/r 3" "gh pr merge, --repo: args"
FAKE_RC=0 gate allow "gh pr merge, --repo=" "$(bash_in 'gh pr merge --repo=o/r 4 --squash')"
called "ready o/r 4" "gh pr merge, --repo=: args"
FAKE_RC=0 gate allow "gh pr merge, a PR URL" "$(bash_in 'gh pr merge https://github.com/o/r/pull/7 --squash')"
called "ready o/r 7" "URL: args"
FAKE_RC=0 gate allow "match-head-commit is passed on" "$(bash_in "gh pr merge 3 -R o/r --squash --match-head-commit $SHA")"
called "ready o/r 3 --expect-head $SHA" "head: args"
FAKE_RC=0 gate allow "gh api merge" "$(bash_in 'gh api repos/o/r/pulls/3/merge -X PUT')"
called "ready o/r 3" "gh api: args"
FAKE_RC=0 gate allow "gh api merge, leading slash" "$(bash_in 'gh api -X PUT /repos/o/r/pulls/5/merge')"
called "ready o/r 5" "gh api slash: args"
FAKE_RC=0 gate allow "MCP merge" "$(mcp_in '{"owner":"o","repo":"r","pullNumber":3}')"
called "ready o/r 3" "MCP: args"
FAKE_RC=0 gate allow "MCP merge with sha" "$(mcp_in "{\"owner\":\"o\",\"repo\":\"r\",\"pullNumber\":8,\"sha\":\"$SHA\"}")"
called "ready o/r 8 --expect-head $SHA" "MCP sha: args"
FAKE_RC=0 gate allow "merge after another command" "$(bash_in 'git -C /a fetch origin && gh pr merge 3 --repo o/r --squash')"
called "ready o/r 3" "compound: args"
FAKE_RC=0 gate allow "merge after a here-string" "$(bash_in $'cat <<< x\ngh pr merge 3 --repo o/r')"
called "ready o/r 3" "here-string: args"

# ── decisions ────────────────────────────────────────────────────────────────────────────────────
FAKE_RC=3 gate deny "ready says unresolved threads" "$(bash_in 'gh pr merge 3 --repo o/r --squash')"
reason_has "threads: exit named" "exit 3"
FAKE_RC=6 FAKE_GATE=head-mismatch gate deny "ready says head mismatch" "$(bash_in "gh pr merge 3 --repo o/r --match-head-commit $SHA")"
reason_has "head mismatch: gate named" "head-mismatch"
FAKE_RC=7 gate deny "ready cannot query" "$(mcp_in '{"owner":"o","repo":"r","pullNumber":3}')"
gate deny "no --repo" "$(bash_in 'gh pr merge 3 --squash')"
reason_has "no repo: asks for it" "--repo"
called "" "no repo: ready not called"
gate deny "no PR number" "$(bash_in 'gh pr merge --repo o/r --squash')"
gate deny "MCP without a number" "$(mcp_in '{"owner":"o","repo":"r"}')"
FAKE_RC=3 gate allow "bypass" "$(bash_in 'PR_CLOSEOUT_OK=1 gh pr merge 3 --repo o/r')"
called "" "bypass: ready not called"
PR_CLOSEOUT_SCRIPT="$tmp/missing.mjs" gate deny "ready script missing" "$(bash_in 'gh pr merge 3 --repo o/r')"
reason_has "script missing: says how to bypass" "PR_CLOSEOUT_OK=1"

# ── not a merge: allowed without asking ──────────────────────────────────────────────────────────
gate allow "merge in a commit message" "$(bash_in 'git commit -m "gh pr merge later"')"
called "" "commit message: ready not called"
gate allow "merge in single quotes" "$(bash_in "echo 'gh pr merge 3 --repo o/r'")"
called "" "quoted: ready not called"
gate allow "git merge" "$(bash_in 'git merge --ff-only origin/main')"
called "" "git merge: ready not called"
gate allow "merge inside a heredoc body" "$(bash_in $'cat > n.md <<EOF\ngh pr merge 3 --repo o/r\nEOF')"
called "" "heredoc: ready not called"
gate allow "nothing about merge" "$(bash_in 'ls -la')"

MIN_PASS=43
if [ "$pass" -lt "$MIN_PASS" ] && [ "${STOP_ON_FAIL:-0}" != 1 ]; then failed "only $pass checks passed, expected at least $MIN_PASS"; fi
echo "pr-merge-gate: $pass passed, $fail failed"

mut_bad=0; mut_n=0
mutant() {   # <label> <substring of the case that must kill it> <perl substitution>
  local label=$1 want=$2 m="$tmp/mutant-$1.sh" log="$tmp/mutant-$1.log" rc first
  perl -pe "$3" "$HOOK" > "$m" || { echo "MUTANT [$label] perl failed"; mut_bad=1; return; }
  if cmp -s "$m" "$HOOK"; then echo "MUTANT [$label] substitution did not apply"; mut_bad=1; return; fi
  HOOK="$m" NO_MUTANTS=1 STOP_ON_FAIL=1 perl -e 'alarm 120; exec @ARGV' bash "$0" > "$log" 2>&1; rc=$?
  mut_n=$((mut_n + 1))
  first=$(command grep -m1 '^FAIL' "$log")
  if [ "$rc" = 0 ]; then echo "MUTANT [$label] suite stayed green"; mut_bad=1
  elif [ -z "$first" ]; then echo "MUTANT [$label] crashed before any case failed"; mut_bad=1
  elif [[ $first != *"$want"* ]]; then echo "MUTANT [$label] killed by [${first:0:90}], expected [$want]"; mut_bad=1
  else echo "mutant [$label]: suite red as required (by [$want])"; fi
}
if [ "${NO_MUTANTS:-0}" != 1 ]; then
  mutant bypass        "[bypass]"                     's/^  case \$cmd in \*PR_CLOSEOUT_OK=1\*\) allow ;; esac$/  :/'
  mutant here-string   "[here-string: args]"          's/my \$s = \$l; \$s =~ s\/<<<\/\/g;/my \$s = \$l;/'
  mutant rc-check      "[ready says unresolved threads]" 's/\[ "\$rc" = 0 \] && continue/continue/'
  mutant need-target   "[no --repo]"                  's/if \[ "\$repo" = - \] \|\| \[ "\$num" = - \]; then/if false; then/'
  mutant expect-head   "[head: args]"                 's/\[ "\$sha" = - \] \|\| args\+=/true || args+=/'
  mutant api-parse     "[gh api: args]"               's/if \(\$x =~ m\{\^\/\?repos/if (0 && \$x =~ m{^\/?repos/'
  mutant mcp           "[MCP: args]"                  's/elif \[\[ \$tool == mcp__\*merge_pull_request \]\]/elif false/'
  MUT_WANT_N=7
  if [ "$mut_n" != "$MUT_WANT_N" ]; then echo "FAIL: $mut_n of $MUT_WANT_N mutants ran"; mut_bad=1; fi
  [ "$mut_bad" = 0 ] || fail=$((fail + 1))
fi
[ "$fail" = 0 ]
