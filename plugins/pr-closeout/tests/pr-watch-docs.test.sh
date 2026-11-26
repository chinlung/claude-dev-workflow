#!/bin/bash
# Docs assertions for plugins/pr-closeout/skills/pr-watch/SKILL.md.
# The stop reasons are defined once, in pr-closeout.mjs (STOP_REASONS); the SKILL's table of them is
# checked against that list both ways. The actions pr-watch never takes may be named only under its
# "## 不做" heading, so no step of the SKILL reads as an instruction to take them.
# Usage: bash plugins/pr-closeout/tests/pr-watch-docs.test.sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
SKILL=${SKILL:-"$here/../skills/pr-watch/SKILL.md"}
SCRIPT=${SCRIPT:-"$here/../scripts/pr-closeout.mjs"}
pass=0; fail=0
ok() { pass=$((pass + 1)); }
failed() { fail=$((fail + 1)); echo "FAIL $1"; }
[ -f "$SKILL" ] || { echo "FAIL SKILL.md missing at $SKILL"; exit 1; }

# frontmatter
fm=$(perl -0ne 'print $1 if /\A---\n(.*?)\n---\n/s' "$SKILL")
if [[ $fm == *"name: pr-watch"* ]]; then ok; else failed "[frontmatter name: pr-watch]"; fi
desc=$(printf '%s\n' "$fm" | perl -ne 'print $1 if /^description:\s*(.*)$/')
if [[ $desc == *"盯 PR"* ]]; then ok; else failed "[description says 盯 PR] $desc"; fi

# stop reasons: the "## 停止原因" table's first column, both ways against STOP_REASONS
script_reasons=$(node --input-type=module -e "import { STOP_REASONS } from '$SCRIPT'; console.log(STOP_REASONS.join('\n'))" | sort)
skill_reasons=$(perl -0ne 'print $1 if /\n## 停止原因[^\n]*\n(.*?)(\n## |\z)/s' "$SKILL" | perl -ne 'print "$1\n" if /^\|\s*`([a-z-]+)`\s*\|/' | sort)
if [ -n "$script_reasons" ]; then ok; else failed "[STOP_REASONS readable from the script]"; fi
if [ "$script_reasons" = "$skill_reasons" ]; then ok
else failed "[the SKILL's stop reasons are STOP_REASONS] script: $(echo $script_reasons) / skill: $(echo $skill_reasons)"; fi

# forbidden actions only under "## 不做"
before=$(perl -0ne 'print $1 if /\A(.*?)\n## 不做/s' "$SKILL")
after=$(perl -0ne 'print $1 if /\n## 不做[^\n]*\n(.*)\z/s' "$SKILL")
if [ -n "$after" ]; then ok; else failed "[a ## 不做 section]"; fi
for s in 'gh pr merge' resolveReviewThread 'gh pr comment' /replies 'git push --delete'; do
  if [[ $before == *"$s"* ]]; then failed "[$s named before ## 不做]"; else ok; fi
done
for s in 'gh pr merge' resolveReviewThread 'gh pr comment'; do
  if [[ $after == *"$s"* ]]; then ok; else failed "[## 不做 names $s]"; fi
done

# the seams the SKILL must name
body=$(cat "$SKILL")
for s in 'watch --start' '--stop' '`stopped`' '`attempt` 是 null' 'watch-ack' '--triage-only' '--repo-dir' 'PushNotification' '/loop' 'run_attempt' '*.local.json' 'ScheduleWakeup'; do
  if [[ $body == *"$s"* ]]; then ok; else failed "[SKILL names $s]"; fi
done

# what a comment says never reaches the ledger as a task: the ledger is printed back into the context by
# the scope-ledger hooks, so a triaged comment goes in as a question for the user, in the model's words
for s in '請使用者裁定' '不照抄留言原文' 'check 名稱'; do
  if [[ $body == *"$s"* ]]; then ok; else failed "[SKILL names $s]"; fi
done

echo "pr-watch-docs: $pass passed, $fail failed"
[ "$fail" = 0 ] && [ "$pass" -ge 28 ]
