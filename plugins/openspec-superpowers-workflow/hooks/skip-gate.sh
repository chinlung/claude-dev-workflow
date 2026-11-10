#!/bin/bash
# openspec-superpowers-workflow PreToolUse skip-gate (v2; matcher Edit|Write|MultiEdit|NotebookEdit).
#
# In an openspec project with no active change under openspec/changes/, a code edit is allowed only
# after the SKIP verdict on the eight contract surfaces has been written down as a declaration file:
#   <project>/.claude/openspec-skip.<session>.local.md, containing one line
#   契約面：API=否 資料=否 schema=否 migration=否 相容=否 權限=否 並行=否 跨模組=否 ｜ 理由：<一句>
# A surface marked 是 denies and asks for the workflow (Phase 1). After the archive gate allowed an
# archive in this session (${TMPDIR}/claude-openspec-archived-<session>), the declaration must be
# newer than that marker: a declaration written before the archive no longer counts. The marker
# only exists for an archive this session's gate allowed, so the declaration must also be newer
# than openspec/changes/archive/ itself, whose mtime moves whenever a change is moved into it: by
# another session, or by an archive that bypassed the gate. Anything else that touches that
# directory's mtime (a checkout that adds or removes an archived change) asks for a fresh
# declaration too.
# Not gated: openspec/ and .claude/ (workflow and declaration writes), paths outside the project,
# and documentation (.md .mdx .txt .rst .adoc, docs/, doc/).
# Every edit in one parallel batch is denied while the file is missing, so v1's batch window and
# session flag are gone. The hook checks that a verdict was written, that every surface has a value
# and that none is 是; it cannot check that the verdict is right. Fail-open: any unexpected
# condition allows.
# Design: docs/openspec-workflow-2-design-2026-11-09.md §4.2. Tests: tests/skip-gate.test.sh
set -uo pipefail

allow() { exit 0; }
trap allow ERR

input=$(cat)
# Cheapest exit first: this hook runs on every edit, and most projects have no openspec/ (cwd is
# only needed when CLAUDE_PROJECT_DIR is unset, so this decides the same way as the check below).
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ ! -d "${CLAUDE_PROJECT_DIR%/}/openspec" ]; then allow; fi
command -v jq >/dev/null 2>&1 || allow

# One jq call for the three fields, joined with US (0x1f): a non-whitespace IFS character keeps empty
# fields in place, where tab (IFS whitespace) would collapse `sid<tab><tab>path` into two fields.
IFS=$'\x1f' read -r session_id cwd file_path < <(printf '%s' "$input" | jq -r '[.session_id // "", .cwd // "", (.tool_input.file_path // .tool_input.notebook_path // "")] | join("\u001f")' 2>/dev/null) || allow
# file names keep safe characters only: a "/" in the id would put the file elsewhere
session_id="${session_id//[^a-zA-Z0-9._-]/_}"; session_id="${session_id:-unknown}"

proj="${CLAUDE_PROJECT_DIR:-$cwd}"
proj="${proj%/}"
[ -n "$proj" ] || allow
[ -d "$proj/openspec" ] || allow

# gated: files inside the project that are not workflow files, declarations or documentation
case "$file_path" in
  "$proj/openspec/"*|"$proj/.claude/"*|"$proj/docs/"*|"$proj/doc/"*|*.md|*.mdx|*.txt|*.rst|*.adoc) allow ;;
  "$proj/"*) : ;;
  *) allow ;;
esac

# an active change (any directory under changes/ other than archive/) means the workflow is running
changes_dir="$proj/openspec/changes"
if [ -d "$changes_dir" ]; then
  active=$(find "$changes_dir" -mindepth 1 -maxdepth 1 -type d ! -name archive 2>/dev/null | head -1)
  [ -z "$active" ] || allow
fi

decl="$proj/.claude/openspec-skip.${session_id}.local.md"
marker="${TMPDIR:-/tmp}/claude-openspec-archived-${session_id}"
# the eight surfaces, defined once: the template the agent is told to write and the keys checked below
keys=(API 資料 schema migration 相容 權限 並行 跨模組)
template='契約面：'; for key in "${keys[@]}"; do template+="${key}=否 "; done; template+='｜ 理由：<一句話>'

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

if [ -f "$marker" ] && { [ ! -f "$decl" ] || [ ! "$decl" -nt "$marker" ]; }; then
  deny "⛔ openspec：本 session 已歸檔 change，這次是歸檔之後的程式碼編輯。它若碰到任何契約面，spec 就會漏掉這次修訂：請開 follow-up change（Phase 1）。確認八面都不命中時，在歸檔之後重新寫聲明檔（歸檔前寫的不算）：${decl}，內容一行：${template}"
elif [ ! -f "$decl" ]; then
  deny "⛔ openspec 專案偵測到程式碼編輯，但 openspec/changes/ 沒有 active change。先判斷這次變更是否碰到八個契約面（public API／data contract／schema／migration／向後相容／安全權限邊界／並行一致性／跨模組行為），把結論寫進聲明檔再重試：${decl}，內容一行，值只能是「是」或「否」：${template}。任何一面是「是」，或行為變更落在 openspec/specs/ 已涵蓋的能力域，就啟動 workflow（Phase 1），不要寫聲明。同一批並行編輯會一起被擋，寫好聲明後全部重試。"
elif [ -d "$changes_dir/archive" ] && [ ! "$decl" -nt "$changes_dir/archive" ]; then
  deny "⛔ openspec：聲明檔寫下之後 openspec/changes/archive/ 有變動（有 change 被歸檔，可能來自其他 session 或略過閘門的歸檔）。歸檔之後的程式碼編輯若碰到任何契約面，spec 就會漏掉這次修訂：請開 follow-up change（Phase 1）。確認八面都不命中時，重新寫聲明檔（歸檔前寫的不算）：${decl}，內容一行：${template}"
fi

# `|| line=""`: grep finding nothing exits 1, which would fire the ERR trap and allow
line=$(grep -m1 -E '^契約面[：:]' "$decl" 2>/dev/null) || line=""
# Only the part before ｜ carries verdicts (理由 is free text). Each key must appear exactly once as a
# whole word with the value 是 or 否: `API=否定`, a second `API=是`, or `API=否` inside 理由 all fail.
verdicts="${line#契約面[：:]}"; verdicts="${verdicts%%｜*}"; verdicts=" ${verdicts%%|*}"
bad=(); hit=()
for key in "${keys[@]}"; do
  n=0; val=""; rest=$verdicts
  while [[ $rest =~ [[:space:]]${key}=([^[:space:]]*)(.*)$ ]]; do
    n=$((n + 1)); val=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[2]}
  done
  if [ "$n" != 1 ] || { [ "$val" != 是 ] && [ "$val" != 否 ]; }; then bad+=("$key")
  elif [ "$val" = 是 ]; then hit+=("$key")
  fi
done
if [ "${#bad[@]}" -gt 0 ]; then
  deny "⛔ openspec：聲明檔格式不符：${bad[*]}（缺少、出現兩次，或值不是「是／否」；理由裡的文字不算）。檔案：${decl}，需要一行：${template}"
fi
if [ "${#hit[@]}" -gt 0 ]; then
  deny "⛔ openspec：聲明標為「是」：${hit[*]}。碰到契約面的變更要走 openspec-superpowers-workflow：先開 change（Phase 1），再動程式碼。"
fi
allow
