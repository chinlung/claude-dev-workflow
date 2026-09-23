#!/bin/bash
# scope-ledger Stop hook
#
# If the ledger still has unticked In-scope items, block the stop ONCE per distinct state: the
# reason lists the items and asks for a status per item — it does NOT ask the model to keep working.
# Whether work continues is the user's last instruction (an authorised autonomous run continues;
# a session the user paused or is conversing in only reports). `stop_hook_active` → allow, so a
# blocked stop that stops again always passes. The unticked list's checksum is remembered per
# session, so a conversation that pauses mid-work is not bounced every turn.
# A repository-controlled ledger (tracked, or reached through a symlink / submodule) is ignored:
# its lines would be quoted into the block reason.
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
proj="${proj%/}"
ledger_usable "$proj" || allow
ledger=$(ledger_path "$proj")

open=$(ledger_unchecked "$ledger")
[ -n "$open" ] || allow
count=$(count_lines "$open")
# cksum: BSD and GNU agree on the first field, unlike md5/shasum tool names
sig=$(printf '%s\n' "$open" | cksum | awk '{print $1}')
case "$sig" in '' | *[!0-9]*) allow ;; esac

state="${TMPDIR:-/tmp}/claude-scope-stop-${session_id}"
# A state path that is a symlink was planted by someone else (shared /tmp): never write through it.
if [ -L "$state" ]; then allow; fi
if [ -f "$state" ] && [ "$(cat "$state" 2>/dev/null)" = "$sig" ]; then allow; fi
printf '%s' "$sig" > "$state" || allow

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name as part of the
# variable name and aborts with "unbound variable".
reason="scope-ledger：帳本 ${ledger} 尚有 ${count} 項 In scope 未完成：
${open}
依使用者的最後指示處理：已授權自主執行→繼續做；否則不要在這一輪開始新工作，只逐項回報狀態——做／延後（附嚴重度、理由、去處：issue／follow-ups／review-notes／won't-fix）／待使用者裁定——然後結束。若已回報、只是在等使用者回覆，直接再結束即可（同一狀態只提醒一次）。"

jq -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
