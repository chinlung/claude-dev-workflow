#!/bin/bash
# session-reflect gate script fixture 測試
# 用法:bash plugins/session-reflect/tests/gate.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../hooks/reflect-gate.sh"
PASS=0; FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---- helpers ----

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

# run_gate <input_json> <tmpdir>
run_gate() {
  printf '%s' "$1" | TMPDIR="$2" bash "$GATE"
}

# check <名稱> <實際輸出> <期望子字串>
check() {
  if echo "$2" | grep -q "$3"; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"
  fi
}

# check_flag <名稱> <flag 路徑> <expect:exists|absent>
check_flag() {
  if [ "$3" = "exists" ] && [ -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  elif [ "$3" = "absent" ] && [ ! -f "$2" ]; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — flag state wrong: $2"; fi
}

ASSISTANT_NORMAL='{"type":"assistant","message":{"content":[{"type":"text","text":"完成了。"}]}}'
ASSISTANT_ASK='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{}}]}}'
ASSISTANT_QUESTION='{"type":"assistant","message":{"content":[{"type":"text","text":"要繼續嗎？"}]}}'

input_json() { # $1=session_id $2=transcript_path $3=stop_hook_active
  printf '{"session_id":"%s","transcript_path":"%s","stop_hook_active":%s}' "$1" "$2" "$3"
}

# ---- cases ----

# 1) stop_hook_active=true → approve
t=$WORK/c1; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
out=$(run_gate "$(input_json c1 "$t/tr.jsonl" true)" "$t")
check "stop_hook_active → approve" "$out" '"approve"'

# 2) 無 transcript_path → approve
t=$WORK/c2; mkdir -p "$t"
out=$(run_gate '{"session_id":"c2","stop_hook_active":false}' "$t")
check "no transcript → approve" "$out" '"approve"'

# 3) transcript < 10 行 → approve
t=$WORK/c3; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 3 "$ASSISTANT_NORMAL"
out=$(run_gate "$(input_json c3 "$t/tr.jsonl" false)" "$t")
check "short transcript → approve" "$out" '"approve"'

# 4) flag 已存在 → approve
t=$WORK/c4; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
touch "$t/claude-session-reflect-c4"
out=$(run_gate "$(input_json c4 "$t/tr.jsonl" false)" "$t")
check "flag exists → approve" "$out" '"approve"'

# 5) transcript 已含 session-reflect 紀錄 → approve
t=$WORK/c5; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 '{"type":"user","message":{"content":[{"type":"text","text":"呼叫 session-reflect plugin 的 reflect skill"}]}}'
out=$(run_gate "$(input_json c5 "$t/tr.jsonl" false)" "$t")
check "already reflected → approve" "$out" '"approve"'

# 6) 最後 assistant 為 AskUserQuestion → approve 且不標記 flag
t=$WORK/c6; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_ASK"
out=$(run_gate "$(input_json c6 "$t/tr.jsonl" false)" "$t")
check "pending AskUserQuestion → approve" "$out" '"approve"'
check_flag "pending AskUserQuestion → no flag" "$t/claude-session-reflect-c6" absent

# 7) 最後 assistant 文字以問句結尾 → approve 且不標記 flag
t=$WORK/c7; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_QUESTION"
out=$(run_gate "$(input_json c7 "$t/tr.jsonl" false)" "$t")
check "question tail → approve" "$out" '"approve"'
check_flag "question tail → no flag" "$t/claude-session-reflect-c7" absent

# 8) 實質 session → block 且標記 flag
t=$WORK/c8; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
out=$(run_gate "$(input_json c8 "$t/tr.jsonl" false)" "$t")
check "substantive → block" "$out" '"block"'
check "block reason mentions reflect skill" "$out" 'reflect skill'
check_flag "substantive → flag created" "$t/claude-session-reflect-c8" exists

# 9) block 後再跑一次(同 session)→ approve
out=$(run_gate "$(input_json c8 "$t/tr.jsonl" false)" "$t")
check "second run after block → approve" "$out" '"approve"'

# 10) jq 不可用 → approve
t=$WORK/c10; mkdir -p "$t"
make_transcript "$t/tr.jsonl" 12 "$ASSISTANT_NORMAL"
STUB=$WORK/stub; mkdir -p "$STUB"
for cmd in bash cat grep wc tail touch tr; do
  ln -s "$(command -v "$cmd")" "$STUB/$cmd"
done
out=$(printf '%s' "$(input_json c10 "$t/tr.jsonl" false)" | env PATH="$STUB" TMPDIR="$t" bash "$GATE")
check "jq missing → approve" "$out" '"approve"'

# ---- summary ----
echo "----------------------------------------"
echo "gate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
