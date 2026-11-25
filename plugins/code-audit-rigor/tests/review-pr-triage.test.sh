#!/bin/bash
# code-audit-rigor: /review-pr --triage-only (commands/review-pr.md) docs assertions.
# pr-watch (pr-closeout plugin) loads this command with --triage-only and relies on it stopping
# after Phase 2: the fix, commit, push, reply and resolve steps are in the same file the model reads,
# so the stop has to be written where those steps begin, not only in the mode's own section.
# 用法：bash plugins/code-audit-rigor/tests/review-pr-triage.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
DOC=${DOC:-"$here/../commands/review-pr.md"}
pass=0; fail=0
ok() { pass=$((pass + 1)); }
failed() { fail=$((fail + 1)); echo "FAIL $1"; }
[ -f "$DOC" ] || { echo "FAIL review-pr.md missing at $DOC"; exit 1; }
doc=$(cat "$DOC")

# the argument hint names the mode
hint=$(perl -ne 'print $1 if /^argument-hint:\s*"(.*)"/' "$DOC")
if [[ $hint == *"--triage-only"* ]]; then ok; else failed "[argument-hint names --triage-only] $hint"; fi
# the mode has its own section before Phase 1, saying what it keeps and where it ends
mode=$(perl -0ne 'print $1 if /\n## 只分類模式[^\n]*\n(.*?)\n## Phase 1/s' "$DOC")
if [ -n "$mode" ]; then ok; else failed "[a 只分類模式 section before Phase 1]"; fi
for want in "--triage-only" "comment-id" "Phase 2" "結束" "review-pr-comments.json"; do
  if [[ $mode == *"$want"* ]]; then ok; else failed "[mode section mentions $want]"; fi
done
# Phase 3 and Phase 4 each open with the stop line, as the first line after the heading
for ph in 3 4; do
  first=$(perl -0ne "print \$1 if /\n## Phase $ph[^\n]*\n+([^\n]+)/" "$DOC")
  if [[ $first == *"只分類模式到此為止"* ]]; then ok; else failed "[Phase $ph opens with 只分類模式到此為止] $first"; fi
done
# the stop names what it skips
stop=$(perl -0ne 'print $1 if /\n## Phase 4[^\n]*\n+([^\n]+)/' "$DOC")
for want in push 回覆 resolve; do
  if [[ $stop == *"$want"* ]]; then ok; else failed "[Phase 4 stop line names $want]"; fi
done

echo "review-pr-triage: $pass passed, $fail failed"
[ "$fail" = 0 ] && [ "$pass" -ge 10 ]
