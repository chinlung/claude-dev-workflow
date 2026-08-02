#!/bin/bash
# session-learning save-session-reminder fixture 測試
# 用法:bash plugins/session-learning/tests/reminder.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMINDER="$SCRIPT_DIR/../hooks/save-session-reminder.sh"
PASS=0; FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# make_transcript <path> <填充行數> <最後一行 JSON(可為空字串)>
make_transcript() {
  local path="$1" lines="$2" last="$3" i=0
  : > "$path"
  while [ "$i" -lt "$lines" ]; do
    echo '{"type":"user","message":{"content":[{"type":"text","text":"work item '"$i"'"}]}}' >> "$path"
    i=$((i+1))
  done
  [ -n "$last" ] && echo "$last" >> "$path"
  return 0
}

run_hook() { # $1=input json  $2=TMPDIR
  printf '%s' "$1" | TMPDIR="$2" bash "$REMINDER"
}

check() { # $1=名稱 $2=實際輸出 $3=期望子字串
  if echo "$2" | grep -q "$3"; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"
  fi
}

check_flag() { # $1=名稱 $2=flag 路徑 $3=expect:exists|absent
  if [ "$3" = "exists" ] && [ -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = "absent" ] && [ ! -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}

input_json() { # $1=session_id $2=transcript_path
  printf '{"session_id":"%s","transcript_path":"%s"}' "$1" "$2"
}

# 1) 無 transcript_path → approve
t=$WORK/c1; mkdir -p "$t"
out=$(run_hook '{"session_id":"c1"}' "$t")
check "no transcript → approve" "$out" '"approve"'

# 2) transcript < 10 行 → approve
t=$WORK/c2; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 3 ""
out=$(run_hook "$(input_json c2 "$t/tr.jsonl")" "$t")
check "short transcript → approve" "$out" '"approve"'

# 3) flag 已存在 → approve
t=$WORK/c3; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 ""
touch "$t/claude-save-session-c3"
out=$(run_hook "$(input_json c3 "$t/tr.jsonl")" "$t")
check "flag exists → approve" "$out" '"approve"'

# 4) 已執行過 /save-session(command 形狀)→ approve
t=$WORK/c4; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 '{"type":"user","message":{"content":[{"type":"text","text":"<command-name>/save-session</command-name>"}]}}'
out=$(run_hook "$(input_json c4 "$t/tr.jsonl")" "$t")
check "command-form ran → approve" "$out" '"approve"'

# 4b) namespaced command 形狀 → approve
t=$WORK/c4b; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 '{"type":"user","message":{"content":[{"type":"text","text":"<command-name>/session-learning:save-session</command-name>"}]}}'
out=$(run_hook "$(input_json c4b "$t/tr.jsonl")" "$t")
check "namespaced command ran → approve" "$out" '"approve"'

# 4c) Skill 呼叫形狀 → approve
t=$WORK/c4c; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"session-learning:save-session"}}]}}'
out=$(run_hook "$(input_json c4c "$t/tr.jsonl")" "$t")
check "skill-form ran → approve" "$out" '"approve"'

# 5) 僅「提及」save-session(討論、CLAUDE.md 注入、Read 檔案輸出)→ 照常 block
t=$WORK/c5; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 '{"type":"user","message":{"content":[{"type":"text","text":"記得之後用 save-session 保存"}]}}'
out=$(run_hook "$(input_json c5 "$t/tr.jsonl")" "$t")
check "mention-only → still block" "$out" '"block"'

# 6) 實質 session → block 且標記 flag
t=$WORK/c6; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 ""
out=$(run_hook "$(input_json c6 "$t/tr.jsonl")" "$t")
check "substantive → block" "$out" '"block"'
check_flag "substantive → flag created" "$t/claude-save-session-c6" exists

# 7) block 後再跑一次(同 session)→ approve
out=$(run_hook "$(input_json c6 "$t/tr.jsonl")" "$t")
check "second run after block → approve" "$out" '"approve"'

# 8) jq 不可用 → approve
t=$WORK/c8; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 ""
STUB=$WORK/stub; mkdir -p "$STUB"
for cmd in bash cat grep wc tail touch tr; do
  ln -s "$(command -v "$cmd")" "$STUB/$cmd"
done
out=$(printf '%s' "$(input_json c8 "$t/tr.jsonl")" | env PATH="$STUB" TMPDIR="$t" bash "$REMINDER")
check "jq missing → approve" "$out" '"approve"'

echo "----------------------------------------"
echo "reminder.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
