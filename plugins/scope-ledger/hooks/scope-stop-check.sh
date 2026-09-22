#!/bin/bash
# scope-ledger Stop hook
#
# If the ledger still has unticked In-scope items, block the stop ONCE per distinct state: the
# reason lists the items and the three legitimate ways out (finish; move to Deferred with reason and
# destination; name the points that need the user's decision). `stop_hook_active` → allow, so a
# blocked stop that stops again always passes. The unticked list's checksum is remembered per
# session, so a conversation that pauses mid-work is not bounced every turn.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
allow() { exit 0; }
trap allow ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || allow

active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')
if [ "$active" = "true" ]; then allow; fi

session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
ledger=$(ledger_path "${proj%/}")
[ -f "$ledger" ] || allow

open=$(ledger_unchecked "$ledger")
[ -n "$open" ] || allow
count=$(printf '%s\n' "$open" | grep -c .)
# cksum: BSD and GNU agree on the first field, unlike md5/shasum tool names
sig=$(printf '%s\n' "$open" | cksum | awk '{print $1}')
case "$sig" in '' | *[!0-9]*) allow ;; esac

state="${TMPDIR:-/tmp}/claude-scope-stop-${session_id}"
if [ -f "$state" ] && [ "$(cat "$state" 2>/dev/null)" = "$sig" ]; then allow; fi
printf '%s' "$sig" > "$state" || allow

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name as part of the
# variable name and aborts with "unbound variable".
reason="scope-ledger：帳本 ${ledger} 尚有 ${count} 項 In scope 未完成：
${open}
請擇一後再結束：①繼續做完 ②確定本輪不做的項目移到 Deferred（附理由與去處：issue／專案記憶／review-notes／won't-fix） ③需要使用者裁定的點在回覆中明列。若以上已處理、只是在等使用者回覆，直接再結束即可（同一狀態只提醒一次）。"

jq -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
