#!/bin/bash
# 從 Claude Code transcript JSONL 機械抽取摩擦事件,供 reflect skill 的「環境摩擦」視角當證據來源。
# 用法:friction-digest.sh <transcript.jsonl>
#   成功 → stdout 一份 JSON(transcript、counts、events、repeated、truncated),exit 0
#   transcript 不存在或無法解析 → stdout {"error": ...},exit 1(skill 依此 fail-open)
# 欄位形狀取自 2026-10-19 實測(tool_result.is_error、attachment.hook_blocking_error);
# 使用者中斷的字樣該次樣本未出現,屬未實測。
# events 是候選不是結論:hidden_failure 在 Bash 印出先前的 log 或測試輸出時也會認出其中的錯誤行,
# 引用前須確認事件確實發生(reflect skill 的錨點實存濾鏡)。
set -uo pipefail

t="${1:-}"
fail() { printf '{"error": "%s"}\n' "$1"; exit 1; }
command -v jq >/dev/null 2>&1 || fail "jq not available"
[ -n "$t" ] && [ -f "$t" ] || fail "transcript not found"

# 只看主迴圈(isSidechain 為子代理),每類事件最多保留 8 筆,counts 照實計數
read -r -d '' PROG <<'JQ'
def clip($n): (if type == "string" then . else tostring end) | .[0:$n];
def text_of: if type == "string" then .
  elif type == "array" then ([.[]? | select(type == "object") | .text? // empty] | join(" "))
  else "" end;
def input_of: if type == "object" then (.command // .file_path // .url // .pattern // tojson) else tostring end;
def error_kind:
  if startswith("Permission for this action was denied by the Claude Code auto mode classifier") then "classifier_denied"
  elif startswith("Permission to use ") and contains("has been denied") then "permission_denied"
  elif test("^PreToolUse:\\S+ hook error") then "hook_blocked"
  elif startswith("Exit code") then "command_failed"
  else "tool_error" end;
# 錯誤訊息形狀:「<來源>: <字樣>」。行首或被引號包住的同樣字樣多半是印出的文件或清單,不算
def hidden_re: ": (operation not permitted|no matches found|command not found|permission denied|failed to verify certificate)";
def hidden_line: [split("\n")[] | select(test(hidden_re; "i"))][0];
def add_event($kind; $tool; $input; $detail; $line):
  .counts[$kind] = ((.counts[$kind] // 0) + 1)
  | if ([.events[] | select(.kind == $kind)] | length) < 8
    then .events += [{kind: $kind, tool: $tool, input: ($input | clip(160)), detail: ($detail | clip(240)), line: $line}]
    else .truncated = true end
  # 重複失敗以輸入的前 160 字分組:agent 重試多半只改命令尾巴(輸出檔名、拿掉 && 後段),
  # 要算成同一操作。2026-10-19 對 536 份 transcript 實測,改用完整輸入分組是拿 3 個漏報換 1 個誤報
  | if $kind == "interrupted" or $kind == "hook_blocking" then .
    else (($tool + "\u0000" + ($input | clip(160))) as $k
          | .fails[$k] = {tool: $tool, input: ($input | clip(160)), times: ((.fails[$k].times // 0) + 1)})
    end;

reduce (inputs | fromjson? | select(type == "object") | select(.isSidechain != true)) as $l
  ({uses: {}, events: [], counts: {}, fails: {}, truncated: false};
   input_line_number as $line
   | if $l.type == "assistant" then
       reduce ($l.message.content[]? | select(type == "object" and .type == "tool_use")) as $u (.;
         .uses[$u.id] = {name: $u.name, input: ($u.input | input_of)})
     elif $l.type == "user" then
       reduce ($l.message.content | if type == "array" then .[] else empty end | select(type == "object")) as $c (.;
         if $c.type == "tool_result" then
           (.uses[$c.tool_use_id] // {name: "?", input: ""}) as $u
           | ($c.content | text_of) as $txt
           | if $c.is_error == true then add_event($txt | error_kind; $u.name; $u.input; $txt; $line)
             elif $u.name == "Bash" then
               (($txt | hidden_line) as $h
                | if $h != null then add_event("hidden_failure"; $u.name; $u.input; $h; $line) else . end)
             else . end
         else . end)
       | if ($l.message.content | text_of | contains("[Request interrupted by user"))
         then add_event("interrupted"; "user"; ""; ($l.message.content | text_of); $line) else . end
     elif $l.type == "attachment" and $l.attachment.type == "hook_blocking_error"
          and ($l.attachment.hookEvent | IN("Stop", "SubagentStop") | not) then
       # blockingError 實測為 {blockingError, command} 物件
       ($l.attachment.blockingError // {}) as $b
       | add_event("hook_blocking"; ($l.attachment.hookName // "?");
                   (if ($b | type) == "object" then ($b.command // "") else "" end);
                   (if ($b | type) == "object" then ($b.blockingError // "") else $b end); $line)
     else . end)
| {transcript: $path, counts, events, truncated,
   repeated: ([.fails[] | select(.times >= 2)] | sort_by(-.times))}
JQ

out=$(jq -nR --arg path "$t" "$PROG" "$t" 2>/dev/null) || fail "transcript could not be parsed"
printf '%s\n' "$out"
