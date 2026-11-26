#!/bin/bash
# pr-closeout PreToolUse guard for pr-watch (matchers: Bash, and every GitHub MCP tool).
#
# While a PR is watched — a .claude/pr-watch.<pr>.local.json says "active": true — writes to GitHub
# are denied: resolving a review thread, commenting, replying, reviewing, hiding a comment, by any
# spelling the guard knows (gh pr|issue comment|review, gh api with a method, body field, --input or
# a GraphQL mutation, curl or wget writing to api.github.com) and every GitHub MCP tool that is not
# a read (get_*, list_*, search_*, pull_request_read, issue_read). pr-watch reads PR comments written by anyone, so this is
# enforced here rather than left to the model's reading of its instructions. Reads go through.
#
# Where the state lives: pr-closeout.mjs watch writes it under --repo-dir, which pr-watch sets to the
# clone the commands run in. The guard looks under $CLAUDE_PROJECT_DIR and, when the call's cwd is
# elsewhere, under the git top level of that cwd.
#
# Matching is loose on purpose: during a watch none of these belongs in a command, and a false deny
# costs the user one "stop watching". With no active watch every call is allowed before jq or git
# start. No environment-variable bypass: the model could set one itself. To act anyway, stop the
# watch (its state then says "active": false).
# Design: openspec/changes/pr-watch/design.md (組成 3). Tests: tests/pr-watch-guard.test.sh
set -u
shopt -s nullglob
input=$(cat) || exit 0

dirs=()
[ -n "${CLAUDE_PROJECT_DIR:-}" ] && dirs+=("$CLAUDE_PROJECT_DIR")
if [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  cwd=${BASH_REMATCH[1]}
  if [ "$cwd" != "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$cwd" ]; then
    top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && [ "$top" != "${CLAUDE_PROJECT_DIR:-}" ] && dirs+=("$top")
  fi
fi
active=
for d in "${dirs[@]}"; do
  for f in "$d"/.claude/pr-watch.*.local.json; do
    # the state file is pretty JSON written by pr-closeout.mjs; any spacing is accepted
    if [[ $(<"$f") =~ \"active\"[[:space:]]*:[[:space:]]*true ]]; then active=$f; break 2; fi
  done
done
[ -n "$active" ] || exit 0

deny() {
  local r="⛔ pr-watch 防護：監看中不做「$1」（狀態檔 $active）。
pr-watch 不把 thread 標成已解決、不在 PR 上留言、回覆或送出 review，這些交給使用者自己做。
確定要做：先請 Claude 停止監看（pr-closeout.mjs watch … --stop，狀態檔的 active 會變成 false），或自己把狀態檔的 \"active\" 改成 false。"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
  printf '%s\n' "$r" >&2; exit 2
}

tool=
[[ $input =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && tool=${BASH_REMATCH[1]}
if [ "$tool" != Bash ]; then
  # an MCP tool the matcher sent here: only names known to read pass, everything else is a write
  op=${tool##*__}
  case $op in get_*|list_*|search_*|pull_request_read|issue_read) exit 0 ;; esac
  deny "MCP $op"
fi

# What this guard is: a tripwire for writes the model makes by habit or by following the wrong part of
# a document (the /review-pr fix-and-reply phases, say), in the spellings a model actually uses. It is
# not a boundary against a model that sets out to get past it — that model can set the state file's
# "active" to false with its edit tool. The boundaries are elsewhere: /review-pr --triage-only has no
# write step, and pr-watch changes nothing a comment asks for until the user confirms the table.
# So the command is normalised once, generally — decoded from JSON (escapes become real whitespace),
# lowercased, quotes and backslashes dropped — and the rules allow what is known to read; three review
# rounds of adding one more spelling each are why it is not a list of ways to write.
# Two views of the same command: $norm, the whole line, for the rules that ask whether a word occurs
# anywhere; and the segmented text below, for whose flags belong to which gh api.
cmd=$input
command -v jq >/dev/null 2>&1 && cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
norm=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]' | tr '\t\r\n' '   ')
norm=${norm//[\"\'\\]/}
ws='[[:space:]]+'
for s in resolvereviewthread addpullrequestreview minimizecomment; do
  [[ $norm == *"$s"* ]] && deny "$s"
done
# the reply endpoint ends in /replies. Denied unless more of a path or a name follows it: a repo or
# directory called replies reads on (/replies/pulls/7), anything else (a space, a quote's remains, ',',
# ')', the end, a bare trailing slash) is the endpoint
rep='/replies([^[:alnum:]_/-]|/?$|/[^[:alnum:]_.-])'
[[ $norm =~ $rep ]] && deny "/replies"
# gh [flags] pr|issue [flags] comment|review
[[ $norm =~ (^|[^[:alnum:]_-])gh($ws[^[:space:]]+)*$ws(pr|issue)($ws[^[:space:]]+)*$ws(comment|review)([[:space:]]|$) ]] && deny "gh ${BASH_REMATCH[3]} ${BASH_REMATCH[5]}"
# gh api: a plain GET only, judged per command segment. Every method given must be GET; any field
# (-f/-F/--field/--raw-field, attached or not) or --input without a GET of its own is a write.
# One pass over the command keeps track of quotes: a separator outside them (| ; & ( ) ` newline)
# starts a new line, i.e. a new segment. Every quote character, every escaped character and every
# separator inside quotes becomes $Q. Each gh api's write signals are read to its segment's end with $Q
# as a space; its GET counts only up to the first $Q, so only an unquoted, unescaped -X GET of its own
# clears it: not a GET of another command, and not a value such as -f 'body= -X GET'. A quote misread
# only widens what is read for writes or narrows what counts as GET.
Q=$'\x1f'
t=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]' | LC_ALL=C awk -v Q="$Q" '
  BEGIN { RS = "\001"; sep = "|;&()`\n" }
  { s = (NR > 1 ? s RS : "") $0 }
  END {
    n = length(s); st = 0; out = ""
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (c == "\\" && st != 1) { i++; d = substr(s, i, 1); out = out Q ((d == "" || index(sep, d)) ? "" : d); continue }
      if (st == 0) {
        if (c == "\047") { st = 1; out = out Q; continue }
        if (c == "\"") { st = 2; out = out Q; continue }
        if (c == "$" && substr(s, i + 1, 1) == "\047") { st = 3; i++; out = out Q; continue }
        out = out (index(sep, c) ? "\n" : c); continue
      }
      if ((st == 1 || st == 3) && c == "\047") { st = 0; out = out Q; continue }
      if (st == 2 && c == "\"") { st = 0; out = out Q; continue }
      if (c == "\\") continue
      if (c == "\047" || c == "\"") { out = out Q; continue }
      out = out (index(sep, c) ? Q : c)
    }
    printf "%s", out
  }')
# a here-string, not a pipe: the loop runs in this shell, so deny's exit ends the hook
while IFS= read -r seg; do
  rest=${seg//[$'\t\r']/ }
  # find gh api with $Q read as a space ("gh" api is gh api), then cut the same length from $rest
  while [[ ${rest//$Q/ } =~ (^|[^[:alnum:]_-])gh$ws(-[^[:space:]]+$ws)*api([[:space:]]|$)(.*)$ ]]; do
    n=${#BASH_REMATCH[4]}; if [ "$n" -gt 0 ]; then rest=${rest: -$n}; else rest=; fi
    own=${rest%%"$Q"*}; w=${rest//$Q/ }; get=
    while [[ $w =~ (^|[[:space:]])(-x|--method)[[:space:]=]*([a-z]+)(.*)$ ]]; do
      [ "${BASH_REMATCH[3]}" = get ] || deny "gh api ${BASH_REMATCH[3]}"
      w=${BASH_REMATCH[4]}
    done
    [[ $own =~ (^|[[:space:]])(-x|--method)[[:space:]=]*get([^a-z]|$) ]] && get=1
    w=${rest//$Q/ }
    if [ -z "$get" ] && [[ $w =~ (^|[[:space:]])(-f|--field|--raw-field|--input) ]]; then deny "gh api ${BASH_REMATCH[2]}"; fi
  done
done <<< "$t"
# a mutation is a GraphQL thing: a repo or path that merely contains the words is a read. Judged on the
# whole line, which is stricter than per segment.
if [[ $norm =~ (^|[^[:alnum:]_-])gh$ws(-[^[:space:]]+$ws)*api([[:space:]]|$) ]]; then
  gql='(^|[[:space:]/])graphql([^[:alnum:]_/-]|$)'
  [[ $norm =~ $gql && $norm == *mutation* ]] && deny "GraphQL mutation"
fi
# curl and wget have no business with GitHub during a watch: pr-watch reads through gh
if [[ $norm =~ (^|[^[:alnum:]_-])(curl|wget)([[:space:]]|$) ]] && [[ $norm == *github.com* ]]; then deny "${BASH_REMATCH[2]} github.com"; fi
exit 0
