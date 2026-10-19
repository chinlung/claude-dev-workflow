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
# pattern 取 Skill tool 呼叫的 JSON 形狀:僅「提及」plugin 名或讀取
# 本 plugin 文件內容(純文字含識別字)的對話不得誤抑制
if grep -q '"skill":"session-reflect:reflect"' "$transcript_path" 2>/dev/null; then approve; fi

# 互動中偵測:最後一則 assistant 訊息在等使用者 → 放行且「不標記 flag」
# (讓路但保留下次觸發權;只有真正 block 才消耗一 session 唯一一次機會)
last_assistant=$(grep -F '"type":"assistant"' "$transcript_path" 2>/dev/null | tail -1 || true)
if [ -n "$last_assistant" ]; then
  # 解析失敗(損毀/截斷的 JSONL)→ 依 fail-open 契約 approve,不猜測續行
  if ! tool_names=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="tool_use") | .name] | join(",")' 2>/dev/null); then approve; fi
  case "$tool_names" in
    *AskUserQuestion*|*ExitPlanMode*) approve ;;
  esac
  # 問句偵測看結尾 400 字窗口,不只看最後一字:收尾問句後常接條列與補充說明
  # (曾漏判「要實作嗎?實作範圍如下:…」後還有五行的訊息)。半形 ? 須後接空白、
  # 結尾或收尾符號,避開 URL 的 ?query 與 shell 的 ${x:?}。jq 以 codepoint 切片,不受 locale 影響。
  # 取捨:窗口內非提問的?(標題、引號轉述、自問自答)也會讓路——flag 不消耗、下次 Stop 再判,
  # 但若那正是 session 的最後一則,該 session 不回顧。舊版的漏判是在互動中觸發並耗掉唯一一次機會,代價不更低
  if ! asks=$(echo "$last_assistant" | jq -r '[.message.content[]? | select(.type=="text") | .text] | last // "" | .[-400:] | test("？|\\?([\\s*)」』\"`]|$)")' 2>/dev/null); then approve; fi
  if [ "$asks" = "true" ]; then approve; fi
fi

# 全部通過:標記 flag 並觸發回顧。reason 帶 transcript 路徑供 skill 跑 friction-digest;
# 以 jq 組 JSON(路徑含引號也合法),先組再標記——組失敗就放行且不消耗 flag
if ! out=$(jq -nc --arg p "$transcript_path" '{decision: "block", reason: ("🔍 Session 收尾回顧:請呼叫 session-reflect:reflect skill 執行回顧。先依 skill 的 Stage 1 快速 triage:routine 或無實質內容、且沒有摩擦事件,直接回報「本次 session 無需回顧:<理由>」即可結束。transcript: " + $p)}'); then approve; fi
touch "$flag_file"
echo "$out"
