#!/bin/bash
# Tests for plugins/pr-closeout/hooks/pr-watch-guard.sh: while a PR is watched (a
# .claude/pr-watch.<pr>.local.json with "active": true under CLAUDE_PROJECT_DIR), the actions pr-watch
# must never take are denied; with no active watch every call goes through untouched.
# Usage: bash plugins/pr-closeout/tests/pr-watch-guard.test.sh   (HOOK=<path> to test a copy)
set -u
here=$(cd "$(dirname "$0")" && pwd)
HOOK=${HOOK:-"$here/../hooks/pr-watch-guard.sh"}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pwg-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
command -v jq >/dev/null 2>&1 || { echo "pr-watch-guard.test: jq is required"; exit 1; }
pass=0; fail=0; LAST=
ok() { pass=$((pass + 1)); }
failed() { fail=$((fail + 1)); echo "FAIL $1"; [ "${STOP_ON_FAIL:-0}" = 1 ] && exit 1; return 0; }

P="$tmp/proj"; mkdir -p "$P/.claude"
bash_in() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
mcp_in() { jq -cn --arg t "$1" '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:{owner:"o",repo:"r",issue_number:1,body:"x"}}'; }
# verdict <label> <want: allow|deny> <input json>
verdict() {
  local out rc
  out=$(printf '%s' "$3" | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>"$tmp/err"); rc=$?
  local got=allow
  if [ "$rc" = 2 ] || [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = deny ]; then got=deny; fi
  if [ "$rc" != 0 ] && [ "$rc" != 2 ]; then failed "[$1] hook exit $rc: $(head -c 200 "$tmp/err")"; return; fi
  if [ "$got" = "$2" ]; then ok; else failed "[$1] $got, expected $2"; fi
  LAST=$out
}
state() { printf '{"version":1,"pr":%s,"active":%s}' "$1" "$2" > "$P/.claude/pr-watch.$1.local.json"; }

# no watch at all
verdict "no state file: gh pr comment" allow "$(bash_in 'gh pr comment 1 -b hi')"
verdict "no state file: MCP comment" allow "$(mcp_in mcp__github__add_issue_comment)"
# an inactive watch
state 1 false
verdict "inactive: gh pr comment" allow "$(bash_in 'gh pr comment 1 -b hi')"
verdict "inactive: resolve" allow "$(bash_in "gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:\"T\"}){thread{isResolved}}}'")"
# an active watch (another PR's state is inactive: one active file is enough)
state 7 true
for c in \
  "gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:\"T\"}){thread{isResolved}}}'" \
  "gh api graphql -f query='mutation{unresolveReviewThread(input:{threadId:\"T\"}){thread{isResolved}}}'" \
  'gh pr comment 7 -b done' \
  'gh pr review 7 --approve' \
  'gh issue comment 7 -b done' \
  'gh api repos/o/r/pulls/7/comments/99/replies -f body=ok' \
  "gh api graphql -f query='mutation{addPullRequestReview(input:{}){clientMutationId}}'" \
  "gh api graphql -f query='mutation{minimizeComment(input:{}){clientMutationId}}'" \
  'cd /x && GH_DEBUG=1 gh pr comment 7 -b "fixed"'; do
  verdict "active: deny $c" deny "$(bash_in "$c")"
done
has_reason() { if [[ $(printf '%s' "$LAST" | jq -r '.hookSpecificOutput.permissionDecisionReason') == *"$1"* ]]; then ok; else failed "[deny reason names $1]"; fi; }
verdict "active: deny gh pr comment (reason)" deny "$(bash_in 'gh pr comment 7 -b x')"
has_reason "pr-watch.7.local.json"
has_reason "停止監看"
for t in mcp__github__add_issue_comment mcp__claude_ai_GitHub_MCP_Server__add_reply_to_pull_request_comment \
  mcp__github__add_comment_to_pending_review mcp__github__pull_request_review_write mcp__github__update_issue_comment; do
  verdict "active: deny MCP $t" deny "$(mcp_in "$t")"
done
for c in 'git status' 'gh pr view 7 --json comments' 'gh pr checks 7' 'node pr-closeout.mjs watch o/r 7 --repo-dir .' 'gh run rerun 77'; do
  verdict "active: allow $c" allow "$(bash_in "$c")"
done
# no CLAUDE_PROJECT_DIR: nothing to read, nothing to deny
out=$(bash_in 'gh pr comment 7 -b x' | env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok; else failed "[no CLAUDE_PROJECT_DIR] rc $rc out $out"; fi

MIN_PASS=25
[ "$pass" -ge "$MIN_PASS" ] || failed "only $pass checks passed, expected at least $MIN_PASS"
echo "pr-watch-guard: $pass passed, $fail failed"

# Each mutant is this suite on a mutated copy of the hook; it must go red on the case named for it.
mut_bad=0; mut_n=0
mutant() {   # <label> <substring of the first failing case> <perl substitution>
  local m="$tmp/mutant-$1.sh" first
  perl -pe "$3" "$HOOK" > "$m"
  if cmp -s "$m" "$HOOK"; then echo "MUTANT [$1] substitution did not apply"; mut_bad=1; return; fi
  mut_n=$((mut_n + 1))
  first=$(HOOK="$m" NO_MUTANTS=1 STOP_ON_FAIL=1 bash "$0" 2>&1 | command grep -a -m1 '^FAIL')
  if [ -z "$first" ]; then echo "MUTANT [$1] suite stayed green"; mut_bad=1
  elif [[ $first != *"$2"* ]]; then echo "MUTANT [$1] killed by [${first:0:90}], expected [$2]"; mut_bad=1
  else echo "mutant [$1]: suite red as required"; fi
}
if [ "${NO_MUTANTS:-0}" != 1 ]; then
  mutant never-active "[active: deny gh api graphql"          's/active=\$f; break/break/'
  mutant no-bash      "[active: deny gh api graphql"          's/\[\[ \$input == \*"\$s"\* \]\] && deny/[[ \$input == *"\$s"* ]] \&\& false \&\& deny/'
  mutant no-mcp       "[active: deny MCP"                     's/\*\x27"tool_name"\x27\*\) deny/*\x27"tool_name"\x27*) exit 0/'
  [ "$mut_n" = 3 ] || { echo "FAIL: $mut_n of 3 mutants ran"; mut_bad=1; }
  [ "$mut_bad" = 0 ] || fail=$((fail + 1))
fi
[ "$fail" = 0 ]
