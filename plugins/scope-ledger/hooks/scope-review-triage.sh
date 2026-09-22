#!/bin/bash
# scope-ledger PostToolUse — matcher: Skill|Agent
#
# Two different things happen here, and only one of them counts:
#   * A Skill call whose name is on the REVIEW ENTRY allowlist (a top-level review / scan / audit
#     command) injects the triage policy AND increments review_rounds — one round per review run.
#   * An Agent dispatch whose subagent_type (or, when that is omitted, description) looks review-
#     like injects the policy only. It never counts: review commands fan out into N parallel
#     subagents (review-pr launches six, a security scan dozens), so counting dispatches would
#     jump the counter by N inside a single review and fire the round-3 warning on the first one.
# From WARN_ROUNDS on, the message adds a convergence warning. With no ledger (or a git-tracked
# one, which is repository-controlled content), the policy is still injected and `init` is
# pointed at. Fires at dispatch time, before the review's own output lands — the policy is read
# before the findings are.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

# Review ENTRY points that count as a round. Anchored full names, plugin prefix optional where a
# skill is commonly invoked bare. Stem matching (review|security|codex…) was tried first and hit
# verification-before-completion, security-ci-setup, codex:setup, codex:status — every plugin
# that ships a helper with one of those words in its name would count as a review.
ENTRY_RE='^(code-audit-rigor:)?review-(branch|pr)$|^pr-review-toolkit:review-pr$|^security-review$|^codex-review-bg$|^codex:(review|adversarial-review)$|^claude-security(:scan)?$|^(security-audit:)?security-audit$|^code-review$|^simplify$|^(multi-agent-debate:)?debate$|^high-precision-dev:start$|^engineering:code-review$'
# One extended regex per line in this file is OR-ed into ENTRY_RE (a user's own review commands).
EXTRA_RE_FILE="${HOME:-/nonexistent}/.claude/scope-ledger-review-patterns"
# Subagent types that get the policy (inject only, never count).
AGENT_RE='review|security|audit|codex|simplif|critic|adversar|verifier|validator|debate'
WARN_ROUNDS=3

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
    printf '%s' "$name" | grep -Eq "$re" || quiet
    counts=1
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
ledger=$(ledger_path "${proj%/}")

n=""
# A tracked ledger is treated as absent: never written to (it would dirty the repo) and never
# trusted (repository-controlled content).
if [ -f "$ledger" ] && ! ledger_tracked "$proj"; then
  if [ "$counts" -eq 1 ]; then
    n=$(ledger_bump_rounds "$ledger" 2>/dev/null || true)
  fi
  case "$n" in '' | *[!0-9]*) n=$(ledger_rounds "$ledger") ;; esac
fi
if [ -n "$n" ] && [ "$n" -gt 0 ]; then tag="${name}@r${n}"; else tag="${name}@r?"; fi

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name (e.g. $tag」)
# as part of the variable name and aborts with "unbound variable".
policy="scope-ledger｜review／scan 的產出是 input、不是工單。每條 finding 先進帳本 ${ledger} triage 再動手：採納→In scope（附「← 來源: ${tag}」）；延後→Deferred（附理由與去處：issue／專案記憶／review-notes／won't-fix）；噪音→Log 一行。未進帳本的 finding 不得直接修。原目標（goal）的 In scope 未全部勾完前，只採納「屬於本次變更且 Must-fix」的 finding，其餘一律 Deferred。"

if [ -n "$n" ]; then
  if [ "$n" -gt 0 ]; then
    msg="${policy} 本分支 review 累計第 ${n} 輪。"
  else
    msg="${policy} 本分支尚未計入任何 review 輪（輪數只在 review 入口 skill 呼叫時累計）。"
  fi
  if [ "$n" -ge "$WARN_ROUNDS" ]; then
    msg="${msg} ⚠️ 收斂告警：已達 ${n} 輪。先在回覆中列出 In scope 剩餘項與 Deferred 清單（/scope-ledger:scope status），確認原目標是否已達成、是否該收尾，再決定要不要再開一輪。"
  fi
else
  msg="${policy} ⚠️ 目前沒有可用的帳本（${ledger} 不存在或已被 git 追蹤），finding 的 triage 無處落地——先 \`/scope-ledger:scope init \"<使用者的原始請求>\"\`，再處理這次 review 的結果。"
fi

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
