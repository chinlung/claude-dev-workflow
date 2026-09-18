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
# pattern 取 command 展開 / Skill 呼叫的執行形狀:僅「提及」(討論、
# CLAUDE.md 注入、Read 檔案輸出)不得誤抑制提醒。
# command 分支綁在**開頭的 JSON 界定引號**上:真實展開時該 text 欄位以
# `"<command-name>` 起頭,而文件或對話裡提到這個標籤時前面是別的字元。
# 少了那個引號,只要 transcript 出現過本 plugin README 的內文(Read 一次就會)
# 就判定「已執行」並永久抑制提醒 —— 與 1.0.1 修掉的 62-命中-0-執行同一類。
# tests/reminder.test.sh 的 5b 直接讀實際 README 餵進 transcript 來守這件事。
# 加引號只會**縮小**匹配集(新 pattern 匹配的字串都含舊 pattern 也匹配的子串),
# 所以它結構上不可能生出新的「誤判已執行」路徑;偽造仍可能但那在加引號前就存在、
# 且上限只是抑制一次提醒。已知耦合:這個 anchor 是位置性的,要求標籤落在 JSON
# 字串欄位開頭。若 Claude Code 日後在同欄位的標籤前多輸出文字,這裡會漏判而多提醒
# 一次 —— 方向是 fail-safe(偏向提醒,永不偽造 approve);case 4 只釘住欄位開頭那種形狀。
if grep -Eq '"<command-name>/(session-learning:)?save-session</command-name>|"skill":"session-learning:save-session"' "$transcript_path" 2>/dev/null; then
  echo '{"decision": "approve"}'
  exit 0
fi

# 標記已提醒（防止迴圈）
touch "$flag_file"

# 提醒使用者
echo '{"decision": "block", "reason": "💡 本次 session 有實質工作內容，建議執行 /save-session 保存經驗。不需要的話直接說「不用」即可結束。"}'
