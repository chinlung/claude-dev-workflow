#!/bin/bash
# scope-ledger PostToolUse — matcher: Skill|Agent
#
# When a review / scan / audit skill is loaded, or a review-type subagent is dispatched, inject the
# triage policy as context and count the round in the ledger. From WARN_ROUNDS on, add a
# convergence warning. With no ledger, still inject the policy and point at `init`.
# Fires at dispatch time (before the review's own output lands), which is the right moment: the
# policy is read before the findings are.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

REVIEW_RE='review|security|audit|codex|simplify|critic|adversar|verif|debate'
WARN_ROUNDS=3

input=$(cat)
command -v jq >/dev/null 2>&1 || quiet
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || quiet

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
case "$tool" in
  Skill) name=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty') ;;
  Agent) name=$(printf '%s' "$input" | jq -r '(.tool_input.subagent_type // "") as $t | if $t == "" then (.tool_input.description // "") else $t end') ;;
  *) quiet ;;
esac
[ -n "$name" ] || quiet
printf '%s' "$name" | grep -Eiq "$REVIEW_RE" || quiet

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || quiet
ledger=$(ledger_path "${proj%/}")

n=""
if [ -f "$ledger" ]; then
  n=$(ledger_bump_rounds "$ledger" 2>/dev/null || true)
  case "$n" in '' | *[!0-9]*) n=$(ledger_rounds "$ledger") ;; esac
fi
tag="$name@r${n:-?}"

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name (e.g. $tag」)
# as part of the variable name and aborts with "unbound variable".
policy="scope-ledger｜review／scan 的產出是 input、不是工單。每條 finding 先進帳本 ${ledger} triage 再動手：採納→In scope（附「← 來源: ${tag}」）；延後→Deferred（附理由與去處：issue／專案記憶／review-notes／won't-fix）；噪音→Log 一行。未進帳本的 finding 不得直接修。原目標（goal）的 In scope 未全部勾完前，只採納「屬於本次變更且 Must-fix」的 finding，其餘一律 Deferred。"

if [ -n "$n" ]; then
  msg="${policy} 本分支 review 累計第 ${n} 輪。"
  if [ "$n" -ge "$WARN_ROUNDS" ]; then
    msg="${msg} ⚠️ 收斂告警：已達 ${n} 輪。先在回覆中列出 In scope 剩餘項與 Deferred 清單（/scope-ledger:scope status），確認原目標是否已達成、是否該收尾，再決定要不要再開一輪。"
  fi
else
  msg="${policy} ⚠️ 目前沒有帳本（${ledger} 不存在），finding 的 triage 無處落地——先 \`/scope-ledger:scope init \"<使用者的原始請求>\"\`，再處理這次 review 的結果。"
fi

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
