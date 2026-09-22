#!/bin/bash
# scope-ledger SessionStart — matcher: startup|resume|compact|clear
#
# When the project has a ledger, print it (first 60 lines) plus the open-item and round counts.
# stdout of a SessionStart hook becomes context, so this is what brings the original goal back
# after a compaction or a resume.
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
ledger=$(ledger_path "${proj%/}")
[ -f "$ledger" ] || quiet
# A git-tracked ledger is repository-controlled text: never replay it into context. Say so in
# one fixed line (no content quoted) so the person can fix the setup.
if ledger_tracked "$proj"; then
  echo "scope-ledger：${ledger} 已被 git 追蹤，屬 repo 控制的內容，本 plugin 不回放、所有 hook 一律忽略它。若這是你的帳本：git rm --cached 該檔並在 .gitignore 加 *.local.md。"
  exit 0
fi

open=$(ledger_unchecked "$ledger")
count=0
if [ -n "$open" ]; then count=$(printf '%s\n' "$open" | grep -c .); fi
rounds=$(ledger_rounds "$ledger")

# Always ${var}: under `set -u`, bash reads a full-width character glued to a name (e.g. $ledger：)
# as part of the variable name and aborts with "unbound variable".
echo "scope-ledger｜工作範圍帳本 ${ledger}：In scope 未完成 ${count} 項、review 累計 ${rounds} 輪。原目標（goal）與清單如下；用 /scope-ledger:scope status 重看、review finding 先進帳本再動手："
head -60 "$ledger"
exit 0
