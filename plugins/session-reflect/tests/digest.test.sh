#!/bin/bash
# friction-digest.sh fixture 測試
# 用法:bash plugins/session-reflect/tests/digest.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
# fixture 形狀取自 2026-10-19 實測的 transcript JSONL(tool_result.is_error、attachment.hook_blocking_error 等)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIGEST="$SCRIPT_DIR/../skills/reflect/scripts/friction-digest.sh"
PASS=0; FAIL=0

# 帶模板:無模板的 mktemp -d 在 macOS 會落到 /var/folders/.../T/,Claude Code sandbox 只准寫 $TMPDIR
TMPBASE="${TMPDIR:-/tmp}"
WORK=$(mktemp -d "${TMPBASE%/}/reflect-digest-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ---- fixture helpers(以 jq 產生,避免手寫 JSON 的跳脫錯誤)----

# use <id> <tool> <input-json> [sidechain]:assistant 的 tool_use
use() {
  jq -nc --arg id "$1" --arg n "$2" --argjson in "$3" --argjson sc "${4:-false}" \
    '{type:"assistant",isSidechain:$sc,message:{content:[{type:"tool_use",id:$id,name:$n,input:$in}]}}'
}
# result <id> <content> <is_error:true|false|null> [sidechain]:user 的 tool_result
result() {
  jq -nc --arg id "$1" --arg c "$2" --argjson e "$3" --argjson sc "${4:-false}" \
    '{type:"user",isSidechain:$sc,message:{content:[({type:"tool_result",tool_use_id:$id,content:$c} + (if $e == null then {} else {is_error:$e} end))]}}'
}
# hookerr <event> <name> <msg>:attachment.hook_blocking_error(blockingError 為物件,2026-10-19 實測形狀)
hookerr() {
  jq -nc --arg ev "$1" --arg n "$2" --arg m "$3" \
    '{type:"attachment",attachment:{type:"hook_blocking_error",hookEvent:$ev,hookName:$n,
      blockingError:{blockingError:$m,command:"node validate-on-plugin-edit.cjs"}}}'
}
# usertext <text>:使用者文字訊息
usertext() {
  jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}'
}
bash_in() { jq -nc --arg c "$1" '{command:$c}'; }

# 失敗不中止整套(set -e 下 $( ) 非零會直接退出),由各 check 逐條報紅
run_digest() { bash "$DIGEST" "$1" || true; }

# check <名稱> <jq 布林運算式> <JSON>
check() {
  if printf '%s' "$3" | jq -e "$2" >/dev/null 2>&1; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — expr: $2 — got: $(printf '%s' "$3" | head -c 400)"
  fi
}

# ---- 主 fixture:每類一筆 + 干擾項 ----
T=$WORK/main.jsonl
{
  use t1 Bash "$(bash_in 'npm test')"                                                   # 1
  result t1 'Exit code 1
3 tests failed' true                                                                     # 2
  use t2 Bash "$(bash_in 'rm -rf build')"                                               # 3
  result t2 'Permission to use Bash with command rm -rf build has been denied.' true     # 4
  use t3 Bash "$(bash_in 'gh pr merge 1')"                                              # 5
  result t3 'Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Merge Without Review].' true  # 6
  use t4 Bash "$(bash_in 'git push')"                                                   # 7
  result t4 'PreToolUse:Bash hook error: [push-nudge.sh]: not reviewed yet' true         # 8
  hookerr PostToolUse PostToolUse:Edit 'Plugin test suite FAILED'                       # 9
  hookerr Stop Stop 'ledger has open items'                                             # 10
  use t5 Bash "$(bash_in 'cp a b')"                                                     # 11
  result t5 'cp: b: Operation not permitted' null                                       # 12
  use t6 Read '{"file_path":"/repo/CLAUDE.md"}'                                         # 13
  result t6 'cp: b: Operation not permitted (quoted in a doc)' null                     # 14 錯誤形狀:只靠「只掃 Bash」擋下
  usertext '[Request interrupted by user]'                                               # 15
  use t7 Bash "$(bash_in 'ls')"                                                         # 16
  result t7 'README.md' false                                                           # 17
  use t8 Bash "$(bash_in 'make lint')" true                                             # 18
  result t8 'Exit code 2' true true                                                     # 19
  echo '{"type":"user","message":{"content":[{"type":"text","text":"broken'             # 20 損毀行
} > "$T"

out=$(bash "$DIGEST" "$T") && rc=0 || rc=$?
check "exit 0 on valid transcript"            '. != null' "$out"
[ "$rc" -eq 0 ] && { PASS=$((PASS+1)); echo "PASS: rc=0"; } || { FAIL=$((FAIL+1)); echo "FAIL: rc=$rc"; }
check "transcript path echoed"                ".transcript == \"$T\"" "$out"
check "command_failed counted"                '.counts.command_failed == 1' "$out"
check "command_failed carries tool+input+line" '[.events[] | select(.kind=="command_failed")][0] | .tool=="Bash" and .input=="npm test" and .line==2' "$out"
check "permission_denied classified"          '.counts.permission_denied == 1' "$out"
check "classifier_denied classified"          '.counts.classifier_denied == 1' "$out"
check "classifier detail keeps reason"        '[.events[] | select(.kind=="classifier_denied")][0].detail | contains("Merge Without Review")' "$out"
check "hook_blocked (PreToolUse) classified"  '.counts.hook_blocked == 1' "$out"
check "PostToolUse hook_blocking counted"     '.counts.hook_blocking == 1' "$out"
check "hook_blocking names the hook"          '[.events[] | select(.kind=="hook_blocking")][0].tool == "PostToolUse:Edit"' "$out"
check "hook_blocking detail is the message"   '[.events[] | select(.kind=="hook_blocking")][0] | .detail == "Plugin test suite FAILED" and .input == "node validate-on-plugin-edit.cjs"' "$out"
check "Stop hook blocking excluded"           '[.events[] | select(.detail | contains("ledger has open items"))] | length == 0' "$out"
check "hidden failure in Bash output found"   '.counts.hidden_failure == 1' "$out"
check "hidden failure is the cp command"      '[.events[] | select(.kind=="hidden_failure")][0] | .input=="cp a b" and .line==12' "$out"
check "same phrase in Read output ignored"    '[.events[] | select(.tool=="Read")] | length == 0' "$out"
check "user interrupt counted"                '.counts.interrupted == 1' "$out"
check "successful result not an event"        '[.events[] | select(.input=="ls")] | length == 0' "$out"
check "sidechain events excluded"             '[.events[] | select(.input=="make lint")] | length == 0' "$out"
check "malformed line skipped, not fatal"     '.counts | length > 0' "$out"
check "nothing truncated"                     '.truncated == false' "$out"

# ---- 藏在成功輸出裡的失敗:只認錯誤訊息形狀(「: 」後接字樣),不認被引用的文件文字 ----
T=$WORK/hidden.jsonl
{
  use h1 Bash "$(bash_in 'cat CONTRIBUTING.md')"
  result h1 '在 sandbox 內會得到 `Operation not permitted`;那是防護在運作' null
  use h2 Bash "$(bash_in 'bash probe.sh')"
  result h2 'Operation not permitted: 3
no matches found: 1' null
  use h3 Bash "$(bash_in 'cp x y; ls')"
  result h3 'start
(eval):1: operation not permitted: plugins/x/hooks/g.sh
done' null
  use h4 Bash "$(bash_in 'git push')"
  result h4 'To https://example.com/r.git
error: could not lock config file .git/config: Operation not permitted' null
} > "$T"
out=$(run_digest "$T")
check "quoted doc text not a hidden failure"  '[.events[] | select(.input=="cat CONTRIBUTING.md")] | length == 0' "$out"
check "line-start phrase not a hidden failure" '[.events[] | select(.input=="bash probe.sh")] | length == 0' "$out"
check "zsh lowercase error line counted"      '[.events[] | select(.input=="cp x y; ls")] | length == 1' "$out"
check "hidden detail is the matching line"    '[.events[] | select(.input=="cp x y; ls")][0].detail == "(eval):1: operation not permitted: plugins/x/hooks/g.sh"' "$out"
check "errno-style trailing error counted"    '[.events[] | select(.input=="git push")][0].detail | endswith(": Operation not permitted")' "$out"

# ---- 重複失敗:同一命令失敗兩次 → repeated ----
T=$WORK/repeat.jsonl
{
  use r1 Bash "$(bash_in 'git switch main')"
  result r1 'error: unable to unlink: Operation not permitted' null
  use r2 Bash "$(bash_in 'git switch main')"
  result r2 'Exit code 128' true
  use r3 Bash "$(bash_in 'git status')"
  result r3 'Exit code 1' true
} > "$T"
out=$(run_digest "$T")
check "repeated lists the twice-failed command" '.repeated == [{"tool":"Bash","input":"git switch main","times":2}]' "$out"

# ---- 只改尾巴的重試(前 160 字相同)算同一操作的重複失敗——刻意的分組,見腳本 add_event 註解 ----
T=$WORK/prefix.jsonl
prefix=$(printf 'p%.0s' $(seq 1 170))
{
  use q1 Bash "$(bash_in "$prefix > out-3.log")"
  result q1 'Exit code 1' true
  use q2 Bash "$(bash_in "$prefix > out-4.log")"
  result q2 'Exit code 1' true
} > "$T"
out=$(run_digest "$T")
check "tail-tweaked retry counts as a repeat" '(.repeated | length) == 1 and .repeated[0].times == 2' "$out"

# ---- 非 Bash 工具的錯誤 → tool_error(2026-10-19 實測:Edit 匹配不到回 <tool_use_error>)----
T=$WORK/toolerr.jsonl
{
  use e1 Edit '{"file_path":"/repo/a.md","old_string":"x","new_string":"y"}'
  result e1 '<tool_use_error>String to replace not found in file.</tool_use_error>' true
} > "$T"
out=$(run_digest "$T")
check "non-Bash tool error → tool_error"     '.counts.tool_error == 1 and .events[0].tool == "Edit" and .events[0].input == "/repo/a.md"' "$out"

# ---- 上限:同類 20 筆 → events 每類最多 8 筆、counts 照實、truncated ----
T=$WORK/cap.jsonl
for i in $(seq 1 20); do
  use "c$i" Bash "$(bash_in "cmd $i")"
  result "c$i" "Exit code 1" true
done > "$T"
out=$(run_digest "$T")
check "counts keep the full total"            '.counts.command_failed == 20' "$out"
check "events capped at 8 per kind"           '[.events[] | select(.kind=="command_failed")] | length == 8' "$out"
check "truncated flagged"                     '.truncated == true' "$out"

# ---- 長輸入被截短 ----
T=$WORK/long.jsonl
long=$(printf 'x%.0s' $(seq 1 500))
{ use l1 Bash "$(bash_in "$long")"; result l1 "Exit code 1 $long" true; } > "$T"
out=$(run_digest "$T")
check "input clipped to 160 chars"            '.events[0].input | length <= 160' "$out"
check "detail clipped to 240 chars"           '.events[0].detail | length <= 240' "$out"

# ---- 無摩擦 → 空結果 ----
T=$WORK/clean.jsonl
{ use k1 Bash "$(bash_in 'ls')"; result k1 'ok' false; } > "$T"
out=$(run_digest "$T")
check "clean transcript → no events"          '.events == [] and .repeated == [] and .counts == {}' "$out"

# ---- transcript 不存在 → exit 1 + error JSON ----
out=$(bash "$DIGEST" "$WORK/nope.jsonl" 2>/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && { PASS=$((PASS+1)); echo "PASS: missing transcript → rc=1"; } || { FAIL=$((FAIL+1)); echo "FAIL: missing transcript rc=$rc"; }
check "missing transcript → error field"      '.error | type == "string"' "$out"

# ---- summary ----
echo "----------------------------------------"
echo "digest.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
