#!/bin/bash
# scope-ledger UserPromptSubmit — once per session, non-blocking
#
# The two gates only fire when a source file is written through Edit/Write or a recognisable shell
# command. A session whose edits never take either path (tooling that rewrites files, a formatter,
# a scaffolder) would never be asked for a ledger. So on the FIRST prompt a person types in a
# session, when the project has no usable ledger, print one line of context that says so and points
# at `init`; nothing is blocked. If the project has open follow-ups, say how many (HIGH first) —
# that is how deferred work stays visible at the start of the next job.
# Prompts injected by the harness (loop / schedule wake-ups) are skipped.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || quiet
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || quiet

src=$(printf '%s' "$input" | jq -r '.source // "user"')
case "$src" in user | sdk) : ;; *) quiet ;; esac
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
flag="${TMPDIR:-/tmp}/claude-scope-prompt-${session_id}"
[ -f "$flag" ] && quiet
touch "$flag" 2>/dev/null || quiet

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || quiet
proj="${proj%/}"
if ledger_usable "$proj"; then quiet; fi

fu=$(followups_path "$proj")
n=0; h=0
if followups_usable "$proj"; then
  n=$(count_lines "$(followups_open "$fu")")
  h=$(count_lines "$(followups_high "$fu")")
fi

# Always ${var} next to non-ASCII text (set -u would otherwise swallow the glued character).
msg="scope-ledger：本專案（${proj}）沒有可用的工作範圍帳本。若這則訊息是一項要動程式碼的工作（而非提問），先 \`/scope-ledger:scope init \"<原話>\"\`；純提問或純文件工作可忽略本提醒（每 session 只提醒一次）。"
if [ "$n" -gt 0 ]; then
  msg="${msg} 另有 follow-ups ${n} 項（HIGH ${h}）待排程——\`/scope-ledger:scope status\` 看清單，用 init 接手。"
fi
printf '%s\n' "$msg"
exit 0
