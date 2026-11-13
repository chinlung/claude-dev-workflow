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
if (process.env.FAKE_SLEEP) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, Number(process.env.FAKE_SLEEP));
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
# --match-head-commit must be a literal 40-hex sha: a variable or a substitution reaches the hook
# unexpanded, and ready would compare the PR's head with that text
gate deny "match-head-commit is a variable" "$(bash_in 'gh pr merge 3 -R o/r --squash --match-head-commit "$SHA"')"
called "" "variable head: ready not called"
reason_has "variable head" "--match-head-commit"
gate deny "match-head-commit is a short sha" "$(bash_in 'gh pr merge 3 -R o/r --squash --match-head-commit=1111111')"
called "" "short head: ready not called"
FAKE_RC=0 gate allow "gh api merge" "$(bash_in 'gh api repos/o/r/pulls/3/merge -X PUT')"
called "ready o/r 3" "gh api: args"
FAKE_RC=0 gate allow "gh api merge, leading slash" "$(bash_in 'gh api -X PUT /repos/o/r/pulls/5/merge')"
called "ready o/r 5" "gh api slash: args"
FAKE_RC=0 gate allow "MCP merge" "$(mcp_in '{"owner":"o","repo":"r","pullNumber":3}')"
called "ready o/r 3" "MCP: args"
FAKE_RC=0 gate allow "MCP merge with sha" "$(mcp_in "{\"owner\":\"o\",\"repo\":\"r\",\"pullNumber\":8,\"sha\":\"$SHA\"}")"
called "ready o/r 8 --expect-head $SHA" "MCP sha: args"
gate deny "MCP sha is not a full sha" "$(mcp_in '{"owner":"o","repo":"r","pullNumber":8,"sha":"main"}')"
called "" "MCP ref name: ready not called"
FAKE_RC=0 gate allow "merge after another command" "$(bash_in 'git -C /a fetch origin && gh pr merge 3 --repo o/r --squash')"
called "ready o/r 3" "compound: args"
FAKE_RC=0 gate allow "merge after a here-string" "$(bash_in $'cat <<< x\ngh pr merge 3 --repo o/r\nx')"
called "ready o/r 3" "here-string: args"
# << inside a quoted string is not a heredoc either: the line that equals its "delimiter" closes nothing
FAKE_RC=0 gate allow "merge after << in double quotes" "$(bash_in $'echo "<<true"\ngh pr merge 3 --repo o/r\ntrue')"
called "ready o/r 3" "dq <<: args"
FAKE_RC=0 gate allow "merge after << in single quotes" "$(bash_in $'echo \'a<<true\'\ngh pr merge 4 --repo o/r\ntrue')"
called "ready o/r 4" "sq <<: args"
# dropping a quoted word must not join the two < around it into <<
FAKE_RC=0 gate allow "merge after two redirects around a quoted word" "$(bash_in $'cat <"README.md"<LICENSE\ngh pr merge 6 --repo o/r\nLICENSE')"
called "ready o/r 6" "redirect join: args"
# quote state carries across lines: a multi-line string that closes where a heredoc opens must not
# pair its closing quote with the delimiter's opening one
FAKE_RC=0 gate allow "merge after a heredoc opened where a multi-line string closes" "$(bash_in $'gh pr comment 5 --body \'line one\nline two\' && cat <<\'EOF\'\nit\'s fine\nEOF\ngh pr merge 5 --repo o/r')"
called "ready o/r 5" "multi-line close: args"
FAKE_RC=0 gate allow "merge after << inside a multi-line string" "$(bash_in $'echo \'a\n<<EOF b\'\ngh pr merge 7 --repo o/r\nEOF')"
called "ready o/r 7" "multi-line <<: args"
# $'…' is a quote in which \' does not close: without it every quote after that one pairs wrongly
FAKE_RC=0 gate allow "merge after an ANSI-C string with an escaped quote" "$(bash_in $'echo $\'it\\\'s\'\ngh pr merge 3 --repo o/r')"
called "ready o/r 3" "ansi-c: args"
FAKE_RC=0 gate allow "merge after a heredoc opened behind an ANSI-C string" "$(bash_in $'echo $\'it\\\'s\' && cat <<EOF\nsay "hi\nEOF\ngh pr merge 4 --repo o/r')"
called "ready o/r 4" "ansi-c heredoc: args"
# a trailing backslash continues the command line: the body starts after the continuation
FAKE_RC=0 gate allow "merge on the continuation line of a heredoc opener" "$(bash_in $'cat <<EOF \\\n&& gh pr merge 8 --repo o/r\nbody\nEOF')"
called "ready o/r 8" "continuation: args"
# "$( … )" is a command of its own: its heredoc counts although the " around it is open, and a lone "
# in the body must not pair with that one
FAKE_RC=0 gate allow "merge after a commit-message heredoc whose body has a lone quote" "$(bash_in $'git commit -m "$(cat <<\'EOF\'\nsay "hi\nEOF\n)"\ngh pr merge 8 --repo o/r')"
called "ready o/r 8" "dq substitution heredoc: args"
# inside $(( … )) a << is a shift, never a heredoc, however many there are
FAKE_RC=0 gate allow "merge between lines that equal two shift operands" "$(bash_in $'true=1; echo $((1<<true<<true))\ntrue\ngh pr merge 8 --repo o/r\ntrue')"
called "ready o/r 8" "two shifts: args"

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

# ── found by review: wrappers, full paths, backticks, endpoint variants, graphql, open heredocs ──
FAKE_RC=0 gate allow "command gh" "$(bash_in 'command gh pr merge 3 --repo o/r')"
called "ready o/r 3" "command gh: args"
FAKE_RC=0 gate allow "env wrapper" "$(bash_in 'env GH_HOST=github.com gh pr merge 4 -R o/r')"
called "ready o/r 4" "env wrapper: args"
FAKE_RC=0 gate allow "full path to gh" "$(bash_in '/opt/homebrew/bin/gh pr merge 5 --repo o/r')"
called "ready o/r 5" "full path: args"
FAKE_RC=0 gate allow "inside backticks" "$(bash_in 'echo `gh pr merge 6 --repo o/r`')"
called "ready o/r 6" "backticks: args"
FAKE_RC=0 gate allow "endpoint with a trailing slash" "$(bash_in 'gh api repos/o/r/pulls/3/merge/ -X PUT')"
called "ready o/r 3" "trailing slash: args"
FAKE_RC=0 gate allow "endpoint with a query string" "$(bash_in 'gh api "repos/o/r/pulls/9/merge?x=1" -X PUT')"
called "ready o/r 9" "query string: args"
gate deny "graphql mergePullRequest" "$(bash_in "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'")"
called "" "graphql: ready not called"
gate deny "graphql auto-merge" "$(bash_in "gh api graphql -f query='mutation{enablePullRequestAutoMerge(input:{pullRequestId:\"x\"}){clientMutationId}}'")"
gate deny "endpoint with a fragment" "$(bash_in "gh api 'repos/o/r/pulls/3/merge#x' -X PUT")"
called "" "fragment: ready not called"
FAKE_RC=0 gate allow "gh api without merge" "$(bash_in 'gh api repos/o/r/pulls/3 --jq .merged')"
called "" "api no merge: ready not called"
FAKE_RC=0 gate allow "a heredoc that never closes" "$(bash_in $'cat <<EOF\ngh pr merge 3 --repo o/r')"
called "ready o/r 3" "open heredoc: args"
# rescanning an unclosed heredoc keeps the quote and nesting state: opened inside "$(, the ) after it
# returns to the outer "
FAKE_RC=0 gate allow "merge after an unclosed heredoc inside a quoted substitution" "$(bash_in $'x="$(echo ${u:-<<NEVER}\n) <<true #"\ngh pr merge 8 --repo o/r\ntrue')"
called "ready o/r 8" "rescan keeps state: args"

# command substitution runs inside double quotes and unquoted heredocs: what it runs counts
FAKE_RC=0 gate allow "substitution in double quotes" "$(bash_in 'echo "merged: $(gh pr merge 3 --repo o/r --squash)"')"
called "ready o/r 3" "dq substitution: args"
FAKE_RC=0 gate allow "substitution in an assignment" "$(bash_in 'x="$(gh pr merge 4 -R o/r)"')"
called "ready o/r 4" "assignment substitution: args"
FAKE_RC=0 gate allow "backticks in double quotes" "$(bash_in 'echo "`gh pr merge 6 --repo o/r`"')"
called "ready o/r 6" "dq backticks: args"
FAKE_RC=0 gate allow "substitution in an unquoted heredoc" "$(bash_in $'cat <<EOF\n$(gh pr merge 5 --repo o/r)\nEOF')"
called "ready o/r 5" "heredoc substitution: args"
gate allow "substitution text in a quoted heredoc" "$(bash_in $'cat <<\'EOF\'\n$(gh pr merge 5 --repo o/r)\nEOF')"
called "" "quoted heredoc: ready not called"
# a # that starts a word comments out the rest of its line: an apostrophe in it must not open a string
FAKE_RC=0 gate allow "merge after a comment with an apostrophe" "$(bash_in $'# don\'t merge yet\ngh pr merge 3 --repo o/r')"
called "ready o/r 3" "comment apostrophe: args"
FAKE_RC=0 gate allow "merge after a trailing comment" "$(bash_in $'true # it\'s\ngh pr merge 4 --repo o/r')"
called "ready o/r 4" "trailing comment: args"
# the plain reading has no comment rule and takes gh anywhere in a segment, as before 1.0.5: the safe side
FAKE_RC=0 gate allow "merge words in a comment are still checked" "$(bash_in '# gh pr merge 3 --repo o/r')"
called "ready o/r 3" "comment text: args"
FAKE_RC=0 gate allow "merge after a comment with an apostrophe inside backticks" "$(bash_in 'echo `# don'"'"'t`; gh pr merge 8 --repo o/r')"
called "ready o/r 8" "backtick comment apostrophe: args"
FAKE_RC=0 gate allow "a merge inside \${…} still runs" "$(bash_in 'echo ${x:-`gh pr merge 9 --repo o/r`}')"
called "ready o/r 9" "brace substitution: args"
# behind a comment with an apostrophe the plain reading sees nothing, so these rest on the ${…} rules alone
FAKE_RC=0 gate allow "behind a comment: # inside \${…}" "$(bash_in $'# isn\'t\necho ${x:- #}; gh pr merge 21 --repo o/r')"
called "ready o/r 21" "behind a comment, brace word: args"
FAKE_RC=0 gate allow "behind a comment: a merge inside \${…}" "$(bash_in $'# isn\'t\necho ${x:-`gh pr merge 22 --repo o/r`}')"
called "ready o/r 22" "behind a comment, brace subs: args"
FAKE_RC=0 gate allow "behind a comment: a quoted } inside \${…}" "$(bash_in $'# isn\'t\necho ${x:-\'}\'}; gh pr merge 23 --repo o/r')"
called "ready o/r 23" "behind a comment, brace quote: args"
# a # right after a substitution closes is part of the same word, not a comment
FAKE_RC=0 gate allow "merge after a # glued to \$( … )" "$(bash_in 'echo $(true)#; gh pr merge 14 --repo o/r')"
called "ready o/r 14" "glued after paren: args"
FAKE_RC=0 gate allow "merge after a # glued to backticks" "$(bash_in 'echo `true`#; gh pr merge 15 --repo o/r')"
called "ready o/r 15" "glued after backtick: args"
# a } inside quotes does not close the ${…}; a substitution in single quotes inside it is text
FAKE_RC=0 gate allow "merge after a quoted } inside \${…}" "$(bash_in "echo \${x:-'}'}; gh pr merge 3 --repo o/r")"
called "ready o/r 3" "brace quoted close: args"
gate allow "substitution text in single quotes inside \${…}" "$(bash_in "echo \${x:-'\$(gh pr merge 3 --repo o/r)'}")"
called "" "brace quoted substitution: ready not called"
FAKE_RC=0 gate allow "merge after a # inside \${…}" "$(bash_in 'echo ${x:- #}; gh pr merge 12 --repo o/r')"
called "ready o/r 12" "brace comment: args"
FAKE_RC=0 gate allow "a quoted gh after a # inside \${…}" "$(bash_in "echo \${x:- #}; 'gh' pr merge 12 --repo o/r")"
called "ready o/r 12" "brace comment, quoted gh: args"
FAKE_RC=0 gate allow "a # inside a word is not a comment" "$(bash_in 'echo x#y; gh pr merge 5 --repo o/r')"
called "ready o/r 5" "mid-word #: args"
# inside backticks a comment ends at the closing backtick: the command after it still runs
FAKE_RC=0 gate allow "merge after a comment inside backticks" "$(bash_in 'echo `# a note`; gh pr merge 6 --repo o/r')"
called "ready o/r 6" "backtick comment: args"
# a $( … ) in a heredoc body may run across lines: the body is scanned as one text, not line by line
FAKE_RC=0 gate allow "a substitution that runs across heredoc lines" "$(bash_in $'cat <<EOF\n$(echo hi\ngh pr merge 7 --repo o/r)\nEOF')"
called "ready o/r 7" "multi-line heredoc substitution: args"
gate allow "merge text in single quotes inside a multi-line heredoc substitution" "$(bash_in $'cat <<EOF\n$(echo \'x\n$(gh pr merge 7 --repo o/r)\ny\')\nEOF')"
called "" "quoted text in a multi-line heredoc substitution: ready not called"
gate allow "merge as plain text in double quotes" "$(bash_in 'echo "run gh pr merge 3 --repo o/r later"')"
called "" "dq plain text: ready not called"

# options that take a value must not lend it as the PR number, and two numbers are not one PR
FAKE_RC=0 gate allow "--subject takes a value" "$(bash_in 'gh pr merge --subject 5 7 --repo o/r --squash')"
called "ready o/r 7" "subject value: args"
FAKE_RC=0 gate allow "-b takes a value" "$(bash_in 'gh pr merge -b 9 3 -R o/r')"
called "ready o/r 3" "-b value: args"
gate deny "two PR numbers" "$(bash_in 'gh pr merge 5 7 --repo o/r')"
called "" "two numbers: ready not called"

# a command string handed to a shell runs too: bash -c, sh -lc, eval
FAKE_RC=0 gate allow "inside bash -c" "$(bash_in "timeout 60 bash -c 'gh pr merge 3 --repo o/r --squash'")"
called "ready o/r 3" "bash -c: args"
FAKE_RC=0 gate allow "inside sh -lc" "$(bash_in "sh -lc 'gh pr merge 5 -R o/r'")"
called "ready o/r 5" "sh -lc: args"
FAKE_RC=0 gate allow "inside eval" "$(bash_in 'eval "gh pr merge 4 --repo o/r"')"
called "ready o/r 4" "eval: args"
# every ready run shares one budget under the hook's own timeout: too little left is a deny
FAKE_RC=0 FAKE_SLEEP=1500 PR_MERGE_GATE_BUDGET=2 gate deny "two merges, budget spent" "$(bash_in 'gh pr merge 3 --repo o/r; gh pr merge 4 --repo o/r')"
reason_has "budget spent: says so" "時間"
called "ready o/r 3" "budget spent: only the first ran"

# ── not a merge: allowed without asking ──────────────────────────────────────────────────────────
gate allow "merge in a commit message" "$(bash_in 'git commit -m "gh pr merge later"')"
called "" "commit message: ready not called"
gate allow "merge in single quotes" "$(bash_in "echo 'gh pr merge 3 --repo o/r'")"
called "" "quoted: ready not called"
gate allow "git merge" "$(bash_in 'git merge --ff-only origin/main')"
called "" "git merge: ready not called"
gate allow "merge inside a heredoc body" "$(bash_in $'cat > n.md <<EOF\ngh pr merge 3 --repo o/r\nEOF')"
called "" "heredoc: ready not called"
gate allow "merge inside a heredoc whose delimiter has punctuation" "$(bash_in $'cat > n.md <<EOF-TEXT\ngh pr merge 3 --repo o/r\nEOF-TEXT')"
called "" "punctuated delimiter: ready not called"
# the string's EOF line is not the delimiter: the body starts after b' closes the string
gate allow "heredoc opened while a string is open" "$(bash_in $'cat <<EOF \'a\nEOF\nb\'\ngh pr merge 3 --repo o/r\nEOF')"
called "" "pending heredoc: ready not called"
gate allow "an escaped quote before a quoted delimiter" "$(bash_in $'grep -c \\\' f <<\'EOF\'\ngh pr merge 3 --repo o/r\nEOF')"
called "" "escaped quote: ready not called"
gate allow "a real heredoc after a shift outside \$(( ))" "$(bash_in $'let x=1<<n\ncat > n.md <<EOF\ngh pr merge 3 --repo o/r\nEOF')"
called "" "rescan after open heredoc: ready not called"
# DELIM) is not a closing line: taking it would drop the commands after it on that line, or the ones
# between an arithmetic shift and a case branch
FAKE_RC=0 gate allow "merge after EOF) on the same line" "$(bash_in $'x=$(cat <<EOF\ntext\nEOF); gh pr merge 9 --repo o/r')"
called "ready o/r 9" "EOF) same line: args"
FAKE_RC=0 gate allow "merge between an arithmetic shift and a case branch" "$(bash_in $'n=1; echo $((1<<n))\ngh pr merge 9 --repo o/r\ncase n in\nn) :;;\nesac')"
called "ready o/r 9" "case branch: args"
gate allow "a lone quote in a comment before a heredoc" "$(bash_in $'# don\'t merge yet\ncat > n.md <<EOF\nit\'s\ngh pr merge 3 --repo o/r\nEOF')"
called "" "comment quote: ready not called"
# the body has no quote of its own: only the heredoc pass skipping the comment keeps its lone quote
# from hiding the << (the tokenizer's own comment rule cannot save this one)
gate allow "a lone quote in a comment before a heredoc with a plain body" "$(bash_in $'# don\'t merge yet\ncat > n.md <<EOF\ngh pr merge 3 --repo o/r\nEOF')"
called "" "comment before a plain heredoc: ready not called"
gate allow "an escaped backslash at the end of the opener line" "$(bash_in $'cat <<EOF \\\\\ngh pr merge 3 --repo o/r\nEOF')"
called "" "even backslashes: ready not called"
gate allow "a real heredoc on the same line as a shift outside \$(( ))" "$(bash_in $'let x=1<<n && cat > n.md <<EOF\ngh pr merge 3 --repo o/r\nEOF')"
called "" "same-line shift: ready not called"
gate allow "the second of two heredocs on one line" "$(bash_in $'cat <<A <<B\nx\nA\ngh pr merge 3 --repo o/r\nB')"
called "" "two heredocs: ready not called"
gate allow "nothing about merge" "$(bash_in 'ls -la')"
# an escape this hook does not decode (\062 is the digit 2) must not be read as other text: the number
# cannot be told, so the merge is denied, never checked against the wrong PR
gate deny "PR number written with an ANSI-C escape" "$(bash_in $'gh pr merge $\'1\\062\' --repo o/r')"
called "" "ansi-c escape in the number: ready not called"
# one line of three fields per merge: a quoted newline glued to the repo splits the line, and the part
# without a PR number is a merge the hook cannot pin — denied as such, not for an empty sha
gate deny "a repo with a quoted newline glued on" "$(bash_in $'gh pr merge 3 --repo o/r\'\nx\'')"
called "" "newline in the repo: ready not called"
reason_has "newline in the repo" "讀不出是哪個 repo"
gate deny "an api path with a quoted newline in the repo" "$(bash_in $'gh api -X PUT \'repos/o/r\nx/pulls/3/merge\'')"
called "" "newline in the api repo: ready not called"
reason_has "newline in the api repo" "讀不出是哪個 repo"
gate deny "MCP merge with a pull number that is not a number" "$(mcp_in '{"owner":"o","repo":"r","pullNumber":"x3"}')"
called "" "MCP odd number: ready not called"
reason_has "MCP odd number" "讀不出是哪個 repo"

# W5-8: merges the lexer (the third reading) reads the way bash does; bash runs every one of them.
# Keep these last: the mutants below run on a copy with only the two older readings, which miss some of
# these, so they must come after every mutant's own case.
lexer_case() { FAKE_RC=0 gate allow "lexer: $1" "$(bash_in "$2")"; called "ready o/r 3" "lexer: $1: args"; }
lexer_case "line continuation before the command"    $'true && \\\ngh pr merge 3 --repo o/r'
lexer_case "a quote inside backticks"                $'echo `\'-#`\ngh pr merge 3 --repo o/r'
lexer_case "a heredoc in backticks in double quotes" $'echo "done: `cat <<EOF\nnote $(true\ngh pr merge 3 --repo o/r)\nEOF`"'
lexer_case "a heredoc closed by EOF) in \$( … )"     $'x=$(cat <<EOF\ntext\nEOF)\ngh pr merge 3 --repo o/r'
lexer_case "a delimiter in mixed quotes"             $'cat <<\'E\'"F"\nit\'s\nEF\ngh pr merge 3 --repo o/r'
lexer_case "double quotes in \$( … ) in double quotes" 'echo "x $(echo "a"; gh pr merge 3 --repo o/r) y"'
lexer_case "a substitution inside \$(( … ))"         'echo $(( $(gh pr merge 3 --repo o/r) 0 ))'
lexer_case "a shift inside \$[ … ]"                  $'echo $[1<<2]\ngh pr merge 3 --repo o/r'

MIN_PASS=205
if [ "$pass" -lt "$MIN_PASS" ] && [ "${STOP_ON_FAIL:-0}" != 1 ]; then failed "only $pass checks passed, expected at least $MIN_PASS"; fi
echo "pr-merge-gate: $pass passed, $fail failed"

mut_bad=0; mut_n=0
# The tokenizer mutants break the two older readings, so every mutant runs on a copy that has only
# those two: with the lexer in the loop it would catch most of what they break and the mutant would
# live. The lexer's own mutants are in openspec's tokenizer-differential.test.sh, where bash judges.
old="$tmp/old-readings.sh"
perl -pe 's/^for my \$mode \(0, 1, 2\) \{$/for my \$mode (0, 1) {/' "$HOOK" > "$old"
mutant() {   # <label> <substring of the case that must kill it> <perl substitution>
  local label=$1 want=$2 m="$tmp/mutant-$1.sh" log="$tmp/mutant-$1.log" rc first
  perl -pe "$3" "$old" > "$m" || { echo "MUTANT [$label] perl failed"; mut_bad=1; return; }
  if cmp -s "$m" "$old"; then echo "MUTANT [$label] substitution did not apply"; mut_bad=1; return; fi
  HOOK="$m" NO_MUTANTS=1 STOP_ON_FAIL=1 perl -e 'alarm 120; exec @ARGV' bash "$0" > "$log" 2>&1; rc=$?
  mut_n=$((mut_n + 1))
  first=$(command grep -a -m1 '^FAIL' "$log")   # -a: a truncated multibyte char must not make GNU grep call the log binary
  if [ "$rc" = 0 ]; then echo "MUTANT [$label] suite stayed green"; mut_bad=1
  elif [ -z "$first" ]; then echo "MUTANT [$label] crashed before any case failed"; mut_bad=1
  elif [[ $first != *"$want"* ]]; then echo "MUTANT [$label] killed by [${first:0:90}], expected [$want]"; mut_bad=1
  else echo "mutant [$label]: suite red as required (by [$want])"; fi
}
if [ "${NO_MUTANTS:-0}" != 1 ]; then
  if cmp -s "$old" "$HOOK"; then echo "FAIL: the copy with the two older readings is the hook itself: the reading loop changed"; mut_bad=1; fi
  mutant bypass       "[bypass]"                     's/^  case \$cmd in \*PR_CLOSEOUT_OK=1\*\) allow ;; esac$/  :/'
  mutant here-string   "[here-string: args]"          's/^.*# not-a-heredoc: here-string$//'
  mutant rc-check      "[ready says unresolved threads]" 's/\[ "\$rc" = 0 \] && continue/continue/'
  mutant need-target   "[no --repo]"                  's/if \[ "\$repo" = - \] \|\| \[ "\$num" = - \]; then/if false; then/'
  mutant expect-head   "[head: args]"                 's/\[ "\$sha" = - \] \|\| args\+=/true || args+=/'
  mutant literal-head  "[match-head-commit is a variable]" 's/^  if \[ "\$sha" != - \] && \[\[ ! \$sha =~ .*$/  if false; then/'
  mutant api-parse     "[gh api merge]"               's/if \(\$x =~ m\{\^\/\?repos/if (0 && \$x =~ m{^\/?repos/'
  mutant mcp           "[MCP: args]"                  's/elif \[\[ \$tool == mcp__\*merge_pull_request \]\]/elif false/'
  mutant wrappers      "[command gh: args]"           's/shift \@t while \@t && !\(\(\$t\[0\] =~ m\{\(\[\^\/\]\+\)\$\}\)\[0\] eq '"'"'gh'"'"'\);/shift \@t while \@t && \$t[0] =~ \/^[A-Za-z_]\\w*=\/;/'
  mutant backticks     "[backticks: args]"            's/\[;&\|\(\)`\\n\]/[;&|()\\n]/'
  mutant open-heredoc  "[open heredoc: args]"         's/^    if \(\@hd\) \{ shift \@hd; \@todo = \@body; \}.*$//'
  mutant no-rescan     "[rescan after open heredoc"   's/^    if \(\@hd\) \{ shift \@hd; \@todo = \@body; \}.*$/    if (\@hd) { push \@keep, \@body; \@hd = (); }/'
  mutant no-carry      "[multi-line close: args]"     's/^      push \@keep, \$l; my \$cont = 0;$/      push \@keep, \$l; my \$cont = 0; \$q = "";/'
  mutant no-pending    "[pending heredoc"             's/if \(\@pend && \$q eq '"''"' && !\$cont\)/if (\@pend \&\& !\$cont)/'
  mutant no-cont       "[continuation: args]"         's/\$cont = 1 if \$i == length\(\$l\) - 1; //'
  mutant no-escape     "[escaped quote"               's/(\$cont = 1 if \$i == length\(\$l\) - 1;) \$i\+\+;/$1/'
  mutant first-only    "[same-line shift"             's/^        push \@pend, \[/        \@pend or push \@pend, [/'
  mutant no-subst      "[dq substitution heredoc: args]" 's/^.*# not-a-heredoc: substitution$//'
  mutant no-arith      "[two shifts: args]"           's/^.*# not-a-heredoc: arithmetic$//'
  mutant no-comment    "[comment quote"               's/^.*# not-a-heredoc: comment$//'
  mutant ansi-tok      "[ansi-c: args]"               's/^.*# ansi-c: tokenizer$//'
  mutant ansi-scan     "[ansi-c heredoc: args]"       's/^.*# not-a-heredoc: ansi-c$//'
  mutant ansi-strip    "[PR number written with an ANSI-C escape]" 's/\$tok \.= "\\\\" unless \$e =~ \/\[\\\\\x27"\]\/; //'
  mutant reset-state   "[rescan keeps state: args]"   's/^    my \(\@pend, \@body\);$/    my (\@pend, \@body); (\$q, \$ar, \@st) = ("", 0);/'
  mutant api-unread    "[graphql mergePullRequest]"   's/out\("- - -\\n"\) if !\$found/out("") if 0 \&\& !\$found/'
  mutant prefilter-case "[graphql auto-merge]"        's/\*\[Mm\]\[Ee\]\[Rr\]\[Gg\]\[Ee\]\*/*merge*/'
  mutant dq-subs       "[dq substitution: args]"      's/^      push \@queue, subs_of\(substr\(.*$//'
  mutant heredoc-subs  "[heredoc substitution: args]" 's/push \@queue, subs_of\(join "\\n", \@body\) unless \$hd\[0\]\[1\]; //'
  mutant comment       "[comment apostrophe: args]"   's/if \(!\$plain && \$ch eq .#. && !defined \$tok/if (0 \&\& !defined \$tok/'
  mutant plain-reading "[comment text: args]"         's/^for my \$mode \(0, 1\) \{$/for my \$mode (0) {/'
  mutant field-blank   "[newline in the repo] reason"  's/^  \[\[ \$num =~ \^\[0-9\]\+\$ \]\] \|\| num=-$/  :/'
  mutant backtick-comment "[backtick comment"         's/^\s*if \(\$bq\) \{.*$//'
  # the plain reading catches what it always caught, so these are pinned to cases only the new rule
  # can save: ones behind a comment with an apostrophe, which the plain reading loses whole
  mutant brace-word    "[behind a comment, brace word: args]"   's/^(\s*)if \(!\$d\) \{.*$/$1if (0) {}/'
  mutant brace-subs    "[behind a comment, brace subs: args]"   's/push \@queue, subs_of\(\$w, 1\); //'
  mutant brace-quote   "[behind a comment, brace quote: args]"  's/^\s*if \(\$x eq "\x27"\) \{ my \$k = index.*$//'
  mutant brace-sq-text "[brace quoted substitution"   's/subs_of\(\$w, 1\)/subs_of(\$w)/'
  mutant per-line-body "[multi-line heredoc substitution: args]" 's/subs_of\(join "\\n", \@body\)/map { subs_of(\$_) } \@body/'
  mutant quoted-hd     "[quoted heredoc: ready not called]" 's/ unless \$hd\[0\]\[1\];/;/'
  mutant takes-value   "[--subject takes a value]"   's/if \(\$takes\{\$x\}\) \{ \$k\+\+; next; \}//'
  mutant two-numbers   "[two PR numbers]"             's/\$num = '"'"'-'"'"' if \$two;//'
  mutant shell-c       "[bash -c: args]"              's/if \(\$s->\[\$m\] =~ \/\^-\[A-Za-z\]\*c\[A-Za-z\]\*\$\/\) \{ push \@queue, \$s->\[\$m \+ 1\] if defined \$s->\[\$m \+ 1\]; last; \}//'
  mutant eval          "[eval: args]"                 's/elsif \(\$w eq '"'"'eval'"'"'\)/elsif (0)/'
  mutant budget        "[two merges, budget spent]"   's/if \[ "\$left" -lt 1000 \]; then/if false; then/'
  mutant quoted-lt     "[dq <<: args]"                's/^.*# not-a-heredoc: quoted$//'
  MUT_WANT_N=44
  if [ "$mut_n" != "$MUT_WANT_N" ]; then echo "FAIL: $mut_n of $MUT_WANT_N mutants ran"; mut_bad=1; fi
  [ "$mut_bad" = 0 ] || fail=$((fail + 1))
fi
[ "$fail" = 0 ]
