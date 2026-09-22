#!/bin/bash
# scope-ledger PreToolUse gate — matcher: Edit|Write|MultiEdit|NotebookEdit
#
# The first edit of a SOURCE file (code / shell / SQL / IaC / CI workflow — not Markdown, JSON,
# plain YAML) in a git worktree that has no scope ledger, or whose ledger is bound to another
# branch, is denied ONCE with a message asking for `/scope-ledger:scope init`. The retry passes:
# the gate forces the scope to be written down, it does not judge it. Same batch-window and
# session-flag mechanics as openspec-superpowers-workflow's skip-gate.sh.
#
# Fail-open everywhere: any unexpected condition exits 0 silently — this hook must never be the
# reason an edit cannot happen.
set -uo pipefail
allow() { exit 0; }
trap allow ERR

# Sibling edits of one parallel batch arrive within milliseconds; a real retry (after the model
# has read the deny and written the ledger) is always later than this window.
BATCH_WINDOW_SECS=5
SRC_RE='\.(php|js|jsx|mjs|cjs|ts|tsx|vue|svelte|py|rb|go|rs|java|kt|kts|scala|swift|m|mm|c|cc|cpp|h|hpp|cs|sh|bash|zsh|sql|tf|hcl)$|(^|/)Dockerfile$|(^|/)\.github/workflows/[^/]+\.ya?ml$'

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || allow

session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
# Sanitise: the flag file name must stay inside TMPDIR (a "/" would make touch fail → fail-open → gate silently off)
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$file_path" ] || allow

proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
proj="${proj%/}"

# Path exemptions come BEFORE the batch window so a sibling write to .claude/ (the ledger
# itself, written right after the deny) is never caught by the window.
case "$file_path" in
  "$proj/.claude/"* | "$proj/openspec/"*) allow ;;
  "$proj/"*) : ;;
  *) allow ;;
esac
printf '%s' "$file_path" | grep -Eq "$SRC_RE" || allow
git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1 || allow

ledger=$(ledger_path "$proj")
if [ -f "$ledger" ]; then
  lb=$(ledger_field "$ledger" branch)
  cb=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  # Empty on either side → cannot compare → fail-open
  if [ -z "$lb" ] || [ -z "$cb" ] || [ "$lb" = "$cb" ]; then allow; fi
  reason="⛔ scope-ledger：帳本 ${ledger} 綁定分支「${lb}」，目前分支是「${cb}」。這是另一項工作：先 \`/scope-ledger:scope done\`（或 \`status\` 看舊帳本）收掉舊的，再 \`/scope-ledger:scope init \"<這次的原始請求>\"\` 建新帳本，然後重試本次編輯（同一並行批次的編輯會一併被攔；本閘每 session 只完整觸發一輪）。"
else
  reason="⛔ scope-ledger：本 session 首次編輯程式碼，但 ${ledger} 不存在。先 \`/scope-ledger:scope init \"<使用者的原始請求，逐字一句>\"\` 建立帳本（goal ＋ In scope 清單），再重試本次編輯。之後 review／scan 的每條 finding 都先進帳本 triage 再動手；結束前 Stop hook 會對照 In scope 未勾項。（同一並行批次的編輯會一併被攔；本閘每 session 只完整觸發一輪。）"
fi

deny() {
  jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Once per session: flag present → deny while inside the batch window, allow after it.
# The window is anchored on the FIRST deny (mtime is never refreshed).
flag_file="${TMPDIR:-/tmp}/claude-scope-gate-${session_id}"
if [ -f "$flag_file" ]; then
  now=$(date +%s) || allow
  # stat semantics differ: GNU/uutils -c %Y is mtime, -f is filesystem mode (may "succeed" with
  # non-numeric output); BSD/macOS only knows -f %m. Try both; non-numeric → allow.
  mtime=$(stat -c %Y "$flag_file" 2>/dev/null || stat -f %m "$flag_file" 2>/dev/null) || allow
  case "$now" in '' | *[!0-9]*) allow ;; esac
  case "$mtime" in '' | *[!0-9]*) allow ;; esac
  if [ $((now - mtime)) -lt "$BATCH_WINDOW_SECS" ]; then deny; fi
  allow
fi
touch "$flag_file"
deny
