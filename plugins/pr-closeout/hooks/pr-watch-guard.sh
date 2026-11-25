#!/bin/bash
# pr-closeout PreToolUse guard for pr-watch (matchers: Bash, and the GitHub MCP tools that comment,
# reply or review).
#
# While a PR is watched — some $CLAUDE_PROJECT_DIR/.claude/pr-watch.<pr>.local.json says
# "active": true — the actions pr-watch must never take are denied: marking a review thread
# resolved, commenting on the PR or an issue, replying to a review comment, submitting a review,
# hiding a comment. pr-watch reads PR comments written by anyone, so this is enforced here rather
# than left to the model's reading of its instructions.
#
# Matching is deliberately loose: the strings below anywhere in a Bash command, quoted or not, deny
# it. During a watch none of them belongs in a command, and a false deny costs the user one "stop
# watching". With no active watch every call is allowed at once, before jq or anything else starts.
# No environment-variable bypass: the model could set one itself. To act anyway, stop the watch
# (its state then says "active": false).
# Design: openspec/changes/pr-watch/design.md (組成 3). Tests: tests/pr-watch-guard.test.sh
set -u
dir=${CLAUDE_PROJECT_DIR:-}
[ -n "$dir" ] || exit 0
shopt -s nullglob
active=
for f in "$dir"/.claude/pr-watch.*.local.json; do
  # the state file is written by pr-closeout.mjs as pretty JSON; any spacing is accepted
  if [[ $(<"$f") =~ \"active\"[[:space:]]*:[[:space:]]*true ]]; then active=$f; break; fi
done
[ -n "$active" ] || exit 0

input=$(cat) || exit 0
deny() {
  local r="⛔ pr-watch 防護：監看中不做「$1」（狀態檔 ${active#"$dir"/}）。
pr-watch 不把 thread 標成已解決、不在 PR 上留言、回覆或送出 review，這些交給使用者自己做。
確定要做：先請 Claude 停止監看（狀態檔的 active 會變成 false），或自己把狀態檔的 \"active\" 改成 false。"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
  printf '%s\n' "$r" >&2; exit 2
}

case $input in
  *'"tool_name":"Bash"'*|*'"tool_name": "Bash"'*) ;;
  # every other tool reaching this hook is one of the MCP comment/reply/review tools of the matcher
  *'"tool_name"'*) deny "GitHub MCP 留言、回覆或 review" ;;
  *) exit 0 ;;
esac
for s in resolveReviewThread 'gh pr comment' 'gh pr review' 'gh issue comment' /replies addPullRequestReview minimizeComment; do
  [[ $input == *"$s"* ]] && deny "$s"
done
exit 0
