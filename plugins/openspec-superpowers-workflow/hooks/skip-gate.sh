#!/bin/bash
# openspec-superpowers-workflow PreToolUse skip-gate:
# openspec 專案內首次程式碼編輯且 openspec/changes/ 無 active change 時 deny 一輪,
# 逼出「SKIP 判定必須逐項核對八項契約面」的明示程序;聲明後重試即放行。
# 全面 fail-open——任何異常路徑都放行,絕不因本 hook 卡死使用者的編輯
# (誤擋代價 > 漏觸發代價;本 gate 只逼判斷發生,不驗證判斷內容)。
set -uo pipefail

allow() { exit 0; }
trap allow ERR

# flag 建立後多少秒內視為同一並行批次:同批手足 Edit/Write 會在毫秒級抵達,
# 若見 flag 逕行放行,首批多檔編輯只攔得住一個(cross-vendor review 抓到的繞過);
# 真正的重試(模型讀完 deny、寫出逐項聲明後)必然晚於此窗。
BATCH_WINDOW_SECS=5

input=$(cat)

# jq 不可用 → 放行
command -v jq >/dev/null 2>&1 || allow

session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
# 消毒:flag 檔名只留安全字元(含 / 時 touch 會失敗→fail-open→gate 靜默失效)
session_id="${session_id//[^a-zA-Z0-9._-]/_}"
cwd=$(echo "$input" | jq -r '.cwd // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

reason="⛔ openspec 專案偵測到程式碼編輯,但 openspec/changes/ 無 active change。SKIP openspec-superpowers-workflow 的判定必須先在回覆中逐項核對八項契約面(public API / data contract / schema / migration / 向後相容 / 安全權限邊界 / 並行一致性 / 跨模組行為)並明示各面結論——任一命中、或行為變更落在 openspec/specs/ 已涵蓋的能力域 → 啟動 workflow(Phase 1);確認全部不命中,聲明後重試本次編輯即可(同一並行批次的編輯會一併被攔;本閘每 session 僅完整觸發一輪)。"

deny() {
  jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# 專案根:CLAUDE_PROJECT_DIR 優先,退回 hook 輸入的 cwd
proj="${CLAUDE_PROJECT_DIR:-$cwd}"
if [ -z "$proj" ]; then allow; fi

# 非 openspec 專案 → 放行
if [ ! -d "$proj/openspec" ]; then allow; fi

# 路徑豁免(必須先於批次窗判斷,否則同批寫 openspec/ 的合法 workflow 動作會被誤傷):
# openspec/ 本身(寫 proposal/spec 是 workflow 動作)、.claude/、專案外路徑、
# 無 file_path 的不明工具形狀
case "$file_path" in
  "$proj/openspec/"*|"$proj/.claude/"*) allow ;;
  "$proj/"*) : ;;
  *) allow ;;
esac

# active change 檢查:changes/ 下存在 archive 以外的子目錄 → workflow 已啟動,放行
changes_dir="$proj/openspec/changes"
if [ -d "$changes_dir" ]; then
  active=$(find "$changes_dir" -mindepth 1 -maxdepth 1 -type d ! -name archive 2>/dev/null | head -1)
  if [ -n "$active" ]; then allow; fi
fi

# 一 session 一輪:flag 已存在時,批次窗內續 deny(攔住同批手足編輯)、窗外放行。
# 不更新 mtime——窗以「第一次 deny」起算,不隨手足編輯滑動。
flag_file="${TMPDIR:-/tmp}/claude-openspec-skip-gate-${session_id}"
if [ -f "$flag_file" ]; then
  now=$(date +%s) || allow
  mtime=$(stat -f %m "$flag_file" 2>/dev/null || stat -c %Y "$flag_file" 2>/dev/null) || allow
  if [ -n "$mtime" ] && [ $((now - mtime)) -lt "$BATCH_WINDOW_SECS" ]; then deny; fi
  allow
fi

# 首次:標記 flag(窗起點)並 deny,要求明示 SKIP 判定
touch "$flag_file"
deny
