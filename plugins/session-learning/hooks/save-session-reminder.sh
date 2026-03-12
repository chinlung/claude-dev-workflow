#!/bin/bash
set -euo pipefail

# 讀取 hook 輸入
input=$(cat)

# 解析欄位（jq 不可用時直接放行）
if ! command -v jq &> /dev/null; then
  echo '{"decision": "approve"}'
  exit 0
fi

session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# 用 flag file 防止同一 session 重複提醒
flag_file="${TMPDIR:-/tmp}/claude-save-session-${session_id}"

if [ -f "$flag_file" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 無 transcript 或檔案不存在 → 放行
if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 檢查 session 實質性：少於 10 行（約 5 輪交流）→ 放行
line_count=$(wc -l < "$transcript_path" 2>/dev/null | tr -d ' ')
if [ "${line_count:-0}" -lt 10 ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 已執行過 /save-session → 放行
if grep -q "save-session" "$transcript_path" 2>/dev/null; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 標記已提醒（防止迴圈）
touch "$flag_file"

# 提醒使用者
echo '{"decision": "block", "reason": "💡 本次 session 有實質工作內容，建議執行 /save-session 保存經驗。不需要的話直接說「不用」即可結束。"}'
