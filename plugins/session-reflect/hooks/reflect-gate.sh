#!/bin/bash
# session-reflect Stop hook 閘門:全面 fail-open——任何異常路徑都 approve,
# 絕不因本 hook 讓使用者無法結束 session(誤擋代價 > 漏觸發代價)。
set -uo pipefail

approve() { echo '{"decision": "approve"}'; exit 0; }
trap approve ERR

input=$(cat)

# jq 不可用 → 放行
command -v jq >/dev/null 2>&1 || approve

session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# 防迴圈硬性第一關:因上一個 Stop hook block 而繼續 → 放行
if [ "$stop_hook_active" = "true" ]; then approve; fi

# 一 session 一次
flag_file="${TMPDIR:-/tmp}/claude-session-reflect-${session_id}"
if [ -f "$flag_file" ]; then approve; fi

# 無 transcript → 放行
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then approve; fi

# 實質性:少於 10 行 → 放行
line_count=$(wc -l < "$transcript_path" 2>/dev/null | tr -d ' ')
if [ "${line_count:-0}" -lt 10 ]; then approve; fi

# 本 session 已執行過回顧(手動 /reflect 或先前觸發)→ 放行
if grep -q "session-reflect" "$transcript_path" 2>/dev/null; then approve; fi

# 互動中偵測:最後一則 assistant 訊息在等使用者 → 放行且「不標記 flag」
# (讓路但保留下次觸發權;只有真正 block 才消耗一 session 唯一一次機會)
last_assistant=$(grep -F '"type":"assistant"' "$transcript_path" 2>/dev/null | tail -1 || true)
if [ -n "$last_assistant" ]; then
  tool_names=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="tool_use") | .name] | join(",")' 2>/dev/null || echo "")
  case "$tool_names" in
    *AskUserQuestion*|*ExitPlanMode*) approve ;;
  esac
  last_text=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="text") | .text] | last // ""' 2>/dev/null || echo "")
  case "$last_text" in
    *"?"|*"？") approve ;;
  esac
fi

# 全部通過:標記 flag 並觸發回顧
touch "$flag_file"
echo '{"decision": "block", "reason": "🔍 Session 收尾回顧:請呼叫 session-reflect plugin 的 reflect skill 執行回顧。先快速 triage:routine 或無實質內容,直接回報「本次 session 無需回顧:<理由>」即可結束。"}'
