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
has_reason "--stop"
for t in mcp__github__add_issue_comment mcp__claude_ai_GitHub_MCP_Server__add_reply_to_pull_request_comment \
  mcp__github__add_comment_to_pending_review mcp__github__pull_request_review_write mcp__github__update_issue_comment; do
  verdict "active: deny MCP $t" deny "$(mcp_in "$t")"
done
for c in 'git status' 'gh pr view 7 --json comments' 'gh pr checks 7' 'node pr-closeout.mjs watch o/r 7 --repo-dir .' 'gh run rerun 77'; do
  verdict "active: allow $c" allow "$(bash_in "$c")"
done
# writes to GitHub by other spellings (security-guidance r1): REST, GraphQL mutations, curl, spacing, -R
for c in \
  'gh api -X POST repos/o/r/issues/7/comments -f body=done' \
  'gh api repos/o/r/issues/7/comments -f body=done' \
  'gh api repos/o/r/issues/7/comments --raw-field body=done' \
  'gh api --method PATCH repos/o/r/issues/comments/5 -f body=x' \
  'gh api -XDELETE repos/o/r/issues/comments/5' \
  'gh api repos/o/r/pulls/7/reviews --input review.json' \
  "gh api graphql -f query='mutation { addComment(input:{subjectId:\"X\",body:\"hi\"}) { clientMutationId } }'" \
  'curl -X POST -H "Authorization: bearer $T" https://api.github.com/repos/o/r/issues/7/comments -d "{\"body\":\"x\"}"' \
  'curl https://api.github.com/repos/o/r/issues/7/comments --data @body.json' \
  'wget --post-data=x https://api.github.com/repos/o/r/issues/7/comments' \
  'gh   pr    comment 7 -b x' \
  'gh -R o/r pr comment 7 -b x' \
  'gh api repos/o/r/issues/7/comments -fbody=x' \
  'gh api repos/o/r/issues/7/comments "-f" "body=x"' \
  "gh api graphql -f query='query{viewer{login}}'" \
  'gh api repos/o/r/issues/7/comments -F title=x' \
  'curl -s https://api.github.com/repos/o/r/pulls/7' \
  'curl --json "{}" https://api.github.com/repos/o/r/issues/7/comments' \
  'curl -T body.json https://api.github.com/repos/o/r/issues/7/comments' \
  "node -e \"fetch('https://api.github.com/graphql',{method:'POST',body:JSON.stringify({query:'mutation{resolveReviewThread(input:{threadId:1}){clientMutationId}}'})})\"" \
  'gh pr --repo o/r review 7 --comment -b x' \
  "gh api repos/o/r/issues/7/comments	-f	body=x" \
  'curl -s https://API.GITHUB.COM/repos/o/r/pulls/7' \
  'gh api repos/o/r/issues/7/comments -f body=x -X GET -X POST' \
  'GH API repos/o/r/issues/7/comments -F body=x' \
  "node -e \"fetch('https://api.github.com/repos/o/r/pulls/7/comments/9/replies',{method:'POST',body:'{}'})\"" \
  'gh api repos/o/r/pulls/7/comments/9/replies/ -X GET' \
  'gh api -X GET repos/o/r/pulls/7/comments/9/replies' \
  "gh api -X GET -f query='mutation{addComment(input:{})}' graphql; echo ok" \
  "echo \$(gh api -X GET -f query='mutation{addComment(input:{})}' graphql)"; do
  verdict "active: deny $c" deny "$(bash_in "$c")"
done
for c in \
  'gh api repos/o/r/pulls/7/comments' \
  'gh api repos/o/r/actions/runs/77 --jq .run_attempt' \
  'gh pr view 7 --comments' \
  'gh api repos/acme/react-xterm/pulls/7/comments --paginate' \
  'gh api repos/acme/mutation-testing/pulls/7/comments --paginate' \
  'gh api repos/acme/mutation-testing/issues/7/comments --paginate' \
  'gh api --paginate repos/acme/replies/pulls/7/comments' \
  'gh api --paginate repos/acme/graphql-mutation-kit/pulls/7/comments' \
  'gh api -X GET repos/o/r/pulls/7/comments -f per_page=100'; do
  verdict "active: allow $c" allow "$(bash_in "$c")"
done
# a GET clears only its own gh api: one of another command, or past a separator, quote or backslash,
# does not (a write flag anywhere on the line still counts, so another command's -f such as cut -f1
# is denied too: a known false deny, deferred until commands are told apart by position)
for c in \
  'gh api -X GET repos/o/r/pulls/7 | cat; gh api repos/o/r/issues/7/comments -f body=x' \
  'gh api --method GET repos/o/r/pulls/7 && gh api repos/o/r/pulls/7/reviews --input r.json' \
  "gh api repos/o/r/issues/7/comments --jq '.[] | .id' -f body=x" \
  'echo "$(gh api -X GET repos/o/r/pulls/7; gh api repos/o/r/issues/7/comments -f body=x)"' \
  "sh -c 'gh api repos/o/r/issues/7/comments -f body=x; gh api -X GET repos/o/r/pulls/7'" \
  "sh -c 'gh api repos/o/r/issues/7/comments \"-f\" body=x'" \
  "bash -c \"gh api repos/o/r/issues/7/comments '-f' body=x\"" \
  "gh api repos/o/r/issues/7/comments \$'\\'|' -f body=x" \
  'gh api repos/o/r/issues/7/comments \; -f body=x' \
  'gh api repos/o/r/issues/7/comments \| -f body=x' \
  'gh api -X GET repos/o/r/pulls/7 $(gh api repos/o/r/issues/7/comments -f body=x)' \
  'gh api repos/o/r/issues/7/comments -f body=x; curl -s https://api.github.com/repos/o/r/pulls/7' \
  $'cat <<\'EOF\'\ndon\'t\nEOF\ngh api -X GET repos/o/r/pulls/7; gh api repos/o/r/issues/7/comments -f body=x'; do
  verdict "active: deny $c" deny "$(bash_in "$c")"
done
# a GET counts only as an unquoted, unescaped argument of its own gh api: quoted or escaped text that
# reads "-X GET" is a value (security-guidance r1)
for c in \
  "gh api repos/o/r/issues/7/comments -f 'body= -X GET'" \
  'gh api repos/o/r/issues/7/comments -f "body= --method GET"' \
  'gh api repos/o/r/issues/7/comments -f body=\ -X\ GET' \
  "sh -c 'gh api repos/o/r/issues/7/comments -f \"body= -X GET\"'" \
  '"gh" api repos/o/r/issues/7/comments -f body=x' \
  '"g"h api repos/o/r/issues/7/comments -f body=x' \
  'gh api repos/o/r/issues/7/comments -f body=x # -X GET' \
  'gh "a"pi repos/o/r/issues/7/comments -f body=x' \
  'g\h api repos/o/r/issues/7/comments -f body=x' \
  'gh api "repos/o/r/pulls/7/comments" -X GET -f per_page=100' \
  'gh "pr" "comment" 7 -b x'; do
  verdict "active: deny $c" deny "$(bash_in "$c")"
done
# arguments that reach gh api from a command substitution or through xargs are its own (security-guidance r2)
for c in \
  'gh api repos/o/r/issues/7/comments $(echo -f body=x)' \
  'gh api repos/o/r/issues/7/comments `echo --input r.json`' \
  'gh api repos/o/r/issues/7/comments -f body=x $(gh api -X GET repos/o/r/pulls/7)' \
  "printf '%s\\n' -f body=x | xargs gh api repos/o/r/issues/7/comments" \
  'echo --input=r.json | xargs -n2 gh api repos/o/r/pulls/7/reviews'; do
  verdict "active: deny $c" deny "$(bash_in "$c")"
done
for c in \
  'gh pr list --json number --jq .[].number | xargs -I{} gh api -X GET repos/o/r/pulls/{}/comments -f per_page=100' \
  'gh api -X GET "repos/o/r/pulls/7/comments" -f per_page=100' \
  '"gh" api -X GET repos/o/r/pulls/7/comments -f per_page=100' \
  'gh api -X GET repos/o/r/pulls/7/comments -f per_page=100 # a note' \
  $'gh api repos/o/r/pulls/7/comments \\\n  -X GET \\\n  -f per_page=100'; do
  verdict "active: allow $c" allow "$(bash_in "$c")"
done
# the watch's state is under the clone the command runs in, not under the session's project dir
Q="$tmp/other"; mkdir -p "$Q/.claude"; git init -q "$Q"
printf '{"version":1,"pr":3,"active":true}' > "$Q/.claude/pr-watch.3.local.json"
E="$tmp/empty"; mkdir -p "$E"
cwd_in() { jq -cn --arg c "$1" --arg d "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
out=$(cwd_in 'gh pr comment 3 -b x' "$Q" | CLAUDE_PROJECT_DIR="$E" bash "$HOOK" 2>/dev/null)
if [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then ok; else failed "[state under the cwd's clone is found] $out"; fi
mkdir -p "$Q/sub"
out=$(cwd_in 'gh pr comment 3 -b x' "$Q/sub" | env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null)
if [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ]; then ok; else failed "[no CLAUDE_PROJECT_DIR, cwd in a watched clone] $out"; fi
out=$(cwd_in 'gh pr comment 3 -b x' "$E" | CLAUDE_PROJECT_DIR="$E" bash "$HOOK" 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok; else failed "[nothing watched anywhere] rc $rc out $out"; fi
# every GitHub MCP tool that is not a read is denied, whatever its server calls it
for t in mcp__github__resolve_review_thread mcp__claude_ai_GitHub_MCP_Server__create_pull_request_review \
  mcp__github__add_pull_request_review_comment mcp__claude_ai_GitHub_MCP_Server__issue_write mcp__github__mark_all_notifications_read mcp__gh__add_issue_comment; do
  verdict "active: deny MCP $t" deny "$(mcp_in "$t")"
done
for t in mcp__github__get_pull_request mcp__claude_ai_GitHub_MCP_Server__pull_request_read \
  mcp__github__list_pull_requests mcp__claude_ai_GitHub_MCP_Server__search_issues mcp__claude_ai_GitHub_MCP_Server__issue_read; do
  verdict "active: allow MCP $t" allow "$(mcp_in "$t")"
done
# the matcher sends every GitHub MCP tool here
m=$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("pr-watch-guard")) | .matcher' "$here/../hooks/hooks.json" | command grep -v '^Bash$')
for t in mcp__github__resolve_review_thread mcp__claude_ai_GitHub_MCP_Server__issue_write mcp__github__get_pull_request mcp__gh__add_issue_comment mcp__GITHUB__get_me mcp__GitHub__resolve_review_thread; do
  if printf '%s' "$t" | perl -ne "exit(/^(?:$m)\$/ ? 0 : 1)"; then ok; else failed "[matcher sends $t to the guard] $m"; fi
done
# no CLAUDE_PROJECT_DIR and no cwd: nothing to read, nothing to deny
out=$(bash_in 'gh pr comment 7 -b x' | env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then ok; else failed "[no CLAUDE_PROJECT_DIR] rc $rc out $out"; fi

MIN_PASS=119
[ "$pass" -ge "$MIN_PASS" ] || failed "only $pass checks passed, expected at least $MIN_PASS"
echo "pr-watch-guard: $pass passed, $fail failed"

# Each mutant is this suite on a mutated copy of the hook; it must go red on the case named for it.
mut_bad=0; mut_n=0
mutant() {   # <label> <substring of the first failing case> <perl substitution>
  local m="$tmp/mutant-$1.sh" first
  perl -pe "$3" "$HOOK" > "$m" || { echo "MUTANT [$1] perl failed"; mut_bad=1; return; }
  if cmp -s "$m" "$HOOK"; then echo "MUTANT [$1] substitution did not apply"; mut_bad=1; return; fi
  mut_n=$((mut_n + 1))
  first=$(HOOK="$m" NO_MUTANTS=1 STOP_ON_FAIL=1 bash "$0" 2>&1 | command grep -a -m1 '^FAIL')
  if [ -z "$first" ]; then echo "MUTANT [$1] suite stayed green"; mut_bad=1
  elif [[ $first != *"$2"* ]]; then echo "MUTANT [$1] killed by [${first:0:90}], expected [$2]"; mut_bad=1
  else echo "mutant [$1]: suite red as required"; fi
}
if [ "${NO_MUTANTS:-0}" != 1 ]; then
  mutant never-active "[active: deny gh api graphql"          's/active=\$f; break/break/'
  mutant no-bash      "[active: deny node -e"                 's/\[\[ \$norm == \*"\$s"\* \]\] && deny/false \&\& deny/'
  mutant no-mcp       "[active: deny MCP"                     's/  deny "MCP \$op"/  exit 0/'
  mutant no-cwd       "[state under the cwd"                  's/dirs\+=\("\$top"\)/:/'
  mutant no-api-write "[active: deny gh api -X POST"          's/^if \[\[ \$norm =~ \(\^\|\[\^\[:alnum:\]_-\]\)gh\$ws\(/if false \&\& [[ \$norm =~ (^|[^[:alnum:]_-])gh\$ws(/'
  mutant no-unquote   "[active: deny gh api repos/o/r/issues/7/comments \"-f\""  's{^norm=\$\{norm//.*$}{:}'
  mutant no-lower     "[active: deny gh api -XDELETE"        's/\| tr .\[:upper:\]. .\[:lower:\]. //'
  mutant no-curl      "[active: deny curl -X POST"            's/^if \[\[ \$norm =~ \(\^\|\[\^\[:alnum:\]_-\]\)\(curl/if false \&\& [[ \$norm =~ (^|[^[:alnum:]_-])(curl/'
  mutant no-xanchor   "[active: allow gh api repos/acme/react-xterm" 's/\(\^\|\[\[:space:\]\]\)\(-x\|--method\)/()(-x|--method)/'
  mutant mutation-any "[active: allow gh api repos/acme/mutation-testing" 's/\$norm =~ \$gql && //'
  mutant gql-substr   "[active: allow gh api --paginate repos/acme/graphql-mutation-kit" 's/^  gql=.*$/  gql=graphql/'
  mutant replies-any  "[active: allow gh api --paginate repos/acme/replies" 's/\$norm =~ \$rep /\$norm == *\/replies* /'
  mutant replies-loose "[active: deny node -e \"fetch(" 's{^rep=.*$}{rep="/replies([[:space:]?]|\$)"}'
  mutant replies-end  "[active: deny gh api -X GET repos/o/r/pulls/7/comments/9/replies]" 's{\|/\?\$\|}{|}'
  mutant gql-loose    "[active: deny gh api -X GET -f query=" 's{^  gql=.*$}{  gql="(^|[[:space:]/])graphql([[:space:]]|\$)"}'
  # which GET belongs to which gh api
  mutant own-is-write "[active: deny sh -c 'gh api repos/o/r/issues/7/comments -f body=x;" 's/own=\$\{rest%%"\$Q"\*\}/own=\$rest/'
  mutant sep-not-q    "[active: deny sh -c 'gh api repos/o/r/issues/7/comments -f body=x;" 's/ \| tr .\|;&\(\)`\\n. "\$Q\$Q\$Q\$Q\$Q\$Q\$Q"//'
  mutant quote-not-q  "[active: deny gh api repos/o/r/issues/7/comments -f 'body= -X GET'" 's/^      \| tr "\S+" "\$Q\$Q\$Q"\)$/      )/'
  mutant gh-quoted    "[active: allow \"gh\" api -X GET"                's/while det=\$\{rest\/\/\$Q\/ \}; \[\[ \$det =~/while [[ \$rest =~/'
  mutant every-get    "[active: deny gh api repos/o/r/issues/7/comments -f body=done" 's/\|\| deny "gh api \$wf"/|| :/'
  mutant count-check  "[active: deny \"g\"h api"               's/^    \[ "\$seen" -le 0 \] \|\| deny "gh api \$wf"$/    :/'
  mutant no-continue  "[active: allow gh api repos/o/r/pulls/7/comments \\" 's/printf .%s. "\$\{cmd\/\/\$.\\\\\\n.\/\}"/printf "%s" "\$cmd"/'
  mutant comment-get  "[active: deny gh api repos/o/r/issues/7/comments -f body=x # -X GET" 's{^      own=\$\{own%%" #"\*\}$}{      :}'
  [ "$mut_n" = 23 ] || { echo "FAIL: $mut_n of 23 mutants ran"; mut_bad=1; }
  [ "$mut_bad" = 0 ] || fail=$((fail + 1))
fi
[ "$fail" = 0 ]
