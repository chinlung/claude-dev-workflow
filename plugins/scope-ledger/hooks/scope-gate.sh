#!/bin/bash
# scope-ledger PreToolUse gate — matcher: Edit|Write|MultiEdit|NotebookEdit
#
# The main thread's first edit of a SOURCE file inside the project's git worktree, when the project
# has no scope ledger, is denied ONCE with a message asking for `/scope-ledger:scope init`. The
# retry passes: the gate forces the scope to be written down, it does not judge it. The ledger is
# per goal, not per branch — switching branches under one goal is normal work and never denied.
# Verdict, exemptions, batch window and session flag live in _gate.sh (shared with the Bash gate).
#
# Fail-open everywhere: any unexpected condition exits 0 silently — this hook must never be the
# reason an edit cannot happen.
set -uo pipefail
allow() { exit 0; }
trap allow ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/_ledger.sh" || allow
. "$here/_gate.sh" || allow

session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[ -n "$file_path" ] || allow

proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || allow
proj="${proj%/}"

verdict=$(gate_verdict "$proj" "$file_path" "$session_id" "$agent_id")
[ "$verdict" = deny ] || allow
gate_deny_json "$(gate_reason "$proj" "${file_path#$proj/}")"
exit 0
