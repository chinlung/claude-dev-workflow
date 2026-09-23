#!/bin/bash
# scope-ledger SessionStart — matcher: startup|resume|compact|clear
#
# When the project has a usable ledger, print its frontmatter and the whole In scope section (never
# truncated — that list is the point), the Deferred and Log counts, and the round count. stdout of a
# SessionStart hook becomes context, so this is what brings the original goal back after a
# compaction or a resume. A repository-controlled ledger is not replayed: one fixed line says so.
# Open follow-ups (the cross-ledger backlog) are announced by count, HIGH first, whether or not a
# ledger exists — deferred work must be visible at the start of the next job, not only in memory.
# Fail-open: any unexpected condition exits 0 silently.
set -uo pipefail
quiet() { exit 0; }
trap quiet ERR

input=$(cat)
command -v jq >/dev/null 2>&1 || quiet
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_ledger.sh" || quiet

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$proj" ] || quiet
proj="${proj%/}"
ledger=$(ledger_path "$proj")

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name (e.g. $ledger：)
# as part of the variable name and aborts with "unbound variable".
if [ -f "$ledger" ]; then
  if ledger_tracked "$proj"; then
    echo "scope-ledger：${ledger} 已被 git 追蹤（或經 symlink／submodule 進入 repo），屬 repo 控制的內容，本 plugin 不回放、所有 hook 一律忽略它。若這是你的帳本：git rm --cached 該檔並在 .gitignore 加 *.local.md。"
  else
    open=$(ledger_unchecked "$ledger")
    count=$(count_lines "$open")
    rounds=$(ledger_rounds "$ledger")
    mode=$(ledger_mode "$ledger")
    deferred=$(count_lines "$(ledger_section "$ledger" Deferred)")
    logn=$(count_lines "$(ledger_section "$ledger" Log)")
    echo "scope-ledger｜工作範圍帳本 ${ledger}：mode ${mode}、In scope 未完成 ${count} 項、Deferred ${deferred} 項、Log ${logn} 行、review 累計 ${rounds} 輪。review／scan 的 finding 先進帳本 triage 再動手；/scope-ledger:scope status 看全文。"
    ledger_frontmatter "$ledger"
    echo "## In scope"
    ledger_section "$ledger" "In scope"
    if [ "$deferred" -gt 0 ]; then
      echo "## Deferred（${deferred} 項）"
      ledger_section "$ledger" Deferred | head -10
      if [ "$deferred" -gt 10 ]; then echo "…（其餘 $((deferred - 10)) 項見 status）"; fi
    fi
  fi
fi

fu=$(followups_path "$proj")
if followups_usable "$proj"; then
  n=$(count_lines "$(followups_open "$fu")")
  h=$(count_lines "$(followups_high "$fu")")
  if [ "$n" -gt 0 ]; then
    echo "scope-ledger｜follow-ups ${n} 項（HIGH ${h}）待排程：${fu}——/scope-ledger:scope status 看清單，用 init 接手其中一項或一批。"
    followups_high "$fu" | head -5
  fi
fi
exit 0
