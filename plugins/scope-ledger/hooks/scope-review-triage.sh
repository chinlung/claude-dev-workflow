#!/bin/bash
# scope-ledger PostToolUse — matcher: Skill|Agent
#
# Three kinds of call reach this hook, and only one of them counts a round:
#   * A Skill call on the REVIEW ENTRY allowlist (a top-level review / scan / audit command)
#     injects the triage policy AND increments review_rounds — one round per review run.
#   * A Skill call on the COMPANION list (the Codex cross-vendor pass that runs alongside
#     /review-branch) injects the policy only: it is the same self-review round, not a new one.
#   * An Agent dispatch whose subagent_type (or, when that is omitted, description) looks review-
#     like injects the policy only. It never counts: review commands fan out into N parallel
#     subagents, so counting dispatches would fire the convergence warning inside the first review.
# The policy depends on the ledger's mode: `converge` (default — findings are input, adopt only
# what belongs to this change plus four explicit exceptions) or `harvest` (the goal itself is to
# find / fix findings — findings ARE the work, batch them by severity). With no usable ledger the
# policy is still injected and `init` is pointed at. Fires at dispatch time, before the review's
# own output lands — the policy is read before the findings are.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

# Anchored full names; plugin prefix optional where a skill is commonly invoked bare. Stem matching
# (review|security|codex…) was tried first and hit verification-before-completion,
# security-ci-setup, codex:setup, codex:status — every helper with one of those words counted.
ENTRY_RE='^(code-audit-rigor:)?review-(branch|pr)$|^pr-review-toolkit:review-pr$|^security-review$|^claude-security(:scan)?$|^(security-audit:)?security-audit$|^code-review$|^simplify$|^(multi-agent-debate:)?debate$|^high-precision-dev:start$|^engineering:code-review$'
COMPANION_RE='^codex-review-bg$|^codex:(review|adversarial-review)$'
# One extended regex per line in this file is OR-ed into ENTRY_RE (a user's own review commands).
EXTRA_RE_FILE="${HOME:-/nonexistent}/.claude/scope-ledger-review-patterns"
# Subagent types that get the policy (inject only, never count).
AGENT_RE='review|security|audit|codex|simplif|critic|adversar|verifier|validator|debate'
WARN_ROUNDS=3          # converge: warn from this round on
HARVEST_EVERY=5        # harvest: status check-in every N rounds

input=$(cat)
command -v jq >/dev/null 2>&1 || quiet
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || quiet

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
counts=0
case "$tool" in
  Skill)
    name=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty')
    [ -n "$name" ] || quiet
    # The skill argument may carry arguments after the name ("review-branch main --focus x").
    name="${name%% *}"
    re="$ENTRY_RE"
    if [ -f "$EXTRA_RE_FILE" ]; then
      extra=$(grep -v '^[[:space:]]*$' "$EXTRA_RE_FILE" 2>/dev/null | grep -v '^#' | paste -sd '|' - 2>/dev/null || true)
      [ -n "$extra" ] && re="$re|$extra"
    fi
    if printf '%s' "$name" | grep -Eq "$re"; then
      counts=1
    elif printf '%s' "$name" | grep -Eq "$COMPANION_RE"; then
      counts=0
    else
      quiet
    fi
    ;;
  Agent)
    name=$(printf '%s' "$input" | jq -r '(.tool_input.subagent_type // "") as $t | if $t == "" then (.tool_input.description // "") else $t end')
    [ -n "$name" ] || quiet
    printf '%s' "$name" | grep -Eiq "$AGENT_RE" || quiet
    ;;
  *) quiet ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || quiet
proj="${proj%/}"
ledger=$(ledger_path "$proj")

n=""; mode="converge"
if ledger_usable "$proj"; then
  if [ "$counts" -eq 1 ]; then
    n=$(ledger_bump_rounds "$ledger" 2>/dev/null || true)
  fi
  case "$n" in '' | *[!0-9]*) n=$(ledger_rounds "$ledger") ;; esac
  mode=$(ledger_mode "$ledger")
fi
if [ -n "$n" ] && [ "$n" -gt 0 ]; then tag="${name}@r${n}"; else tag="${name}@r?"; fi

fu=$(followups_path "$proj")
fu_high=0
if followups_usable "$proj"; then fu_high=$(count_lines "$(followups_high "$fu")"); fi

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name (e.g. $tag」)
# as part of the variable name and aborts with "unbound variable".
head="scope-ledger｜review／scan 的產出是 input、不是工單。每條 finding 先進帳本 ${ledger} triage 再動手，附「← 來源: ${tag}」。"
converge="分四類：①採納（現在修）——屬本次變更引入或直接相關；或可利用的安全 finding（講得出誰攻擊／做什麼／拿到什麼，且修在本次觸碰的範圍內）；或同一缺陷的其他實例（sibling，一次改齊）；或專案 MUST 守則命中；或 boy-scout（<10 行、零退化風險、實際改善）。②延後（Deferred：附嚴重度 HIGH／MEDIUM／LOW、理由、去處）——真問題但不屬本次；延後是排程不是裁決，HIGH 安全項必須有 issue 或下一個 goal。③需使用者裁定——業務決策／取捨／範圍。④噪音／won't-fix——只記 Log 一行，須附反證錨點（file:line）。未進帳本的 finding 不得直接修；原目標 In scope 未全勾前，不屬①的一律②，別把這一輪滾成新目標。"
harvest="本帳本 mode 是 harvest（goal 本身就是找／修 finding）：finding 就是工單——全部進 In scope，依嚴重度 HIGH→MEDIUM→LOW 分批、每批一個 PR；LOW 或可利用性不確定者可進 Deferred（附嚴重度與去處）而非丟棄；誤報須附反證錨點記 Log。"

if [ -n "$n" ]; then
  if [ "$mode" = harvest ]; then
    msg="${head} ${harvest}"
  else
    msg="${head} ${converge}"
  fi
  if [ "$n" -gt 0 ]; then
    msg="${msg} 本 goal review 累計第 ${n} 輪。"
  else
    msg="${msg} 本 goal 尚未計入任何 review 輪（輪數只在 review 入口 skill 呼叫時累計）。"
  fi
  if [ "$mode" = harvest ]; then
    if [ "$n" -gt 0 ] && [ $((n % HARVEST_EVERY)) -eq 0 ]; then
      msg="${msg} 📋 每 ${HARVEST_EVERY} 輪盤點：列出已完成／In scope 剩餘／Deferred 與 follow-ups，確認是否該收尾（/scope-ledger:scope status）。"
    fi
  elif [ "$n" -ge "$WARN_ROUNDS" ]; then
    msg="${msg} ⚠️ 收斂告警：已達 ${n} 輪。先在回覆中列出 In scope 剩餘項與 Deferred 清單（/scope-ledger:scope status），確認原目標是否已達成、是否該收尾，再決定要不要再開一輪。"
  fi
else
  msg="${head} ${converge} ⚠️ 目前沒有可用的帳本（${ledger} 不存在或已被 git 追蹤），finding 的 triage 無處落地——先 \`/scope-ledger:scope init \"<使用者的原始請求>\"\`，再處理這次 review 的結果。"
fi
if [ "$fu_high" -gt 0 ]; then
  msg="${msg} 本 repo follow-ups 尚有 HIGH ${fu_high} 項未排程（${fu}）。"
fi

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
