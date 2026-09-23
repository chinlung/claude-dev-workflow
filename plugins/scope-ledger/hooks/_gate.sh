#!/bin/bash
# Shared "deny once per session" gate for the two PreToolUse hooks (Edit/Write and Bash). Sourced.
# Requires _ledger.sh to be sourced first.
#
# Source files are what the security push-nudge calls source: code, shell, SQL, IaC, CI workflows.
# Markdown / JSON / plain YAML never trigger the gate.
SRC_RE='\.(php|js|jsx|mjs|cjs|ts|tsx|vue|svelte|py|rb|go|rs|java|kt|kts|scala|swift|m|mm|c|cc|cpp|h|hpp|cs|sh|bash|zsh|sql|tf|hcl)$|(^|/)Dockerfile$|(^|/)\.github/workflows/[^/]+\.ya?ml$'
# Sibling edits of one parallel batch arrive within milliseconds; a real retry (after the model has
# read the deny and written the ledger) is always later than this window.
BATCH_WINDOW_SECS=5

# gate_verdict <proj> <abs_path> <session_id> <agent_id> [any] → prints "deny" when this edit must
# be denied, nothing otherwise. Never exits; every unexpected condition is "allow".
#   * paths under <proj>/.claude/ and <proj>/openspec/, and paths outside <proj>, pass
#   * non-source paths pass (unless the 5th argument is "any": a patch whose targets are unknown)
#   * subagents pass without touching the flag (they have no user request to write a goal from, and
#     consuming the flag would leave the main thread ungated)
#   * a project that is not a git worktree passes; a project with a ledger file passes
#   * otherwise deny once per session: the flag is shared by both gate hooks, so an Edit and a Bash
#     write in the same session consume the same single deny
gate_verdict() {
  local proj="${1%/}" fp="$2" sid="$3" aid="$4" anyfile="${5:-}" flag now mtime
  [ -n "$proj" ] || return 0
  [ -n "$fp" ] || return 0
  case "$fp" in
    "$proj/.claude/"* | "$proj/openspec/"*) return 0 ;;
    "$proj/"*) : ;;
    *) return 0 ;;
  esac
  if [ "$anyfile" != any ]; then
    printf '%s' "$fp" | grep -Eq "$SRC_RE" || return 0
  fi
  [ -z "$aid" ] || return 0
  git -C "$proj" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  [ -f "$(ledger_path "$proj")" ] && return 0
  sid="${sid//[^a-zA-Z0-9._-]/_}"
  flag="${TMPDIR:-/tmp}/claude-scope-gate-${sid}"
  if [ -f "$flag" ]; then
    now=$(date +%s 2>/dev/null) || return 0
    # stat semantics differ: GNU/uutils -c %Y is mtime, -f is filesystem mode (may "succeed" with
    # non-numeric output); BSD/macOS only knows -f %m. Try both; non-numeric → allow.
    mtime=$(stat -c %Y "$flag" 2>/dev/null || stat -f %m "$flag" 2>/dev/null) || return 0
    case "$now" in '' | *[!0-9]*) return 0 ;; esac
    case "$mtime" in '' | *[!0-9]*) return 0 ;; esac
    if [ $((now - mtime)) -lt "$BATCH_WINDOW_SECS" ]; then echo deny; fi
    return 0
  fi
  touch "$flag" 2>/dev/null || return 0
  echo deny
}

# gate_reason <proj> <shown-path> → the deny message (same for both channels)
gate_reason() {
  local proj="${1%/}" shown="$2" ledger
  ledger=$(ledger_path "$proj")
  # Always ${var}: under `set -u`, bash reads a full-width character glued to a bare variable name
  # as part of the name and aborts with "unbound variable".
  printf '%s' "⛔ scope-ledger：本 session 首次改動程式碼（${shown}），但 ${ledger} 不存在。先 \`/scope-ledger:scope init \"<使用者的原始請求，逐字一句>\"\` 建立帳本（goal、mode、In scope 清單），再重試本次操作。之後 review／scan 的每條 finding 都先進帳本 triage 再動手；結束前 Stop hook 會對照 In scope 未勾項。（同一並行批次的編輯會一併被攔；本閘每 session 只完整觸發一輪，Edit 與 Bash 兩條管道共用。）"
}

# gate_deny_json <reason> → the PreToolUse deny decision on stdout
gate_deny_json() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
}
