#!/bin/bash
# validate-on-plugin-edit.cjs fixture 測試
# 用法:bash scripts/hooks/validate-on-plugin-edit.test.sh
# 消費者:提交前手跑 + CI(.github/workflows/validate.yml)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/validate-on-plugin-edit.cjs"
PASS=0; FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

check() { # <名稱> <實際> <期望子字串>
  if echo "$2" | grep -q "$3"; then PASS=$((PASS+1)); echo "PASS: $1"
  else FAIL=$((FAIL+1)); echo "FAIL: $1 — got: $2"; fi
}

# make_root <dir> [with-failing-suite]:建 scratch 專案根
# stub runner 與 stub suites 都把執行記錄 append 到 <dir>/ran.log
make_root() {
  local r="$1"
  mkdir -p "$r/scripts" "$r/plugins/x/hooks" "$r/plugins/x/tests"
  printf '#!/usr/bin/env node\nrequire("fs").appendFileSync(process.env.RAN_LOG,"runner\\n");\n' > "$r/scripts/validate-fixtures.cjs"
  printf '#!/bin/bash\necho ok >> "$RAN_LOG"\nexit 0\n' > "$r/plugins/x/tests/ok.test.sh"
  if [ "${2:-}" = "with-failing-suite" ]; then
    printf '#!/bin/bash\necho fail-suite ran >&2\nexit 1\n' > "$r/plugins/x/tests/zz-fail.test.sh"
  fi
  : > "$r/plugins/x/hooks/h.sh"
}

# run_hook <root> <file_path> → 全域 rc/out/err
run_hook() {
  rc=0
  out=$(printf '{"tool_input":{"file_path":"%s"}}' "$2" \
    | CLAUDE_PROJECT_DIR="$1" RAN_LOG="$1/ran.log" node "$HOOK" 2>"$1/stderr.txt") || rc=$?
  err=$(cat "$1/stderr.txt" 2>/dev/null || true)
}

# 1) 編輯 plugins/*/hooks/*.sh → 觸發:node runner 與 bash suite 都要跑,exit 0
r=$WORK/r1; make_root "$r"
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "1 hooks/*.sh 觸發後 exit 0" "$rc" '^0$'
check "1 node runner 有跑" "$(cat "$r/ran.log" 2>/dev/null)" 'runner'
check "1 bash suite 有跑" "$(cat "$r/ran.log" 2>/dev/null)" 'ok'

# 2) 編輯 plugins/*/tests/*.test.sh → 觸發(原 /tests/ 涵蓋),bash suite 要跑
r=$WORK/r2; make_root "$r"
run_hook "$r" "$r/plugins/x/tests/ok.test.sh"
check "2 tests/ 編輯觸發 bash suite" "$(cat "$r/ran.log" 2>/dev/null)" 'ok'

# 3) 任一 bash suite 失敗 → exit 2 且 stderr 含失敗輸出
r=$WORK/r3; make_root "$r" with-failing-suite
run_hook "$r" "$r/plugins/x/hooks/h.sh"
check "3 suite 失敗 → exit 2" "$rc" '^2$'
check "3 stderr 帶回失敗輸出" "$err" 'fail-suite ran'

# 4) 無關檔案 → no-op:exit 0 且什麼都沒跑
r=$WORK/r4; make_root "$r"
run_hook "$r" "$r/README.md"
check "4 無關檔案 exit 0" "$rc" '^0$'
if [ -f "$r/ran.log" ]; then
  FAIL=$((FAIL+1)); echo "FAIL: 4 無關檔案不應觸發任何執行 — ran.log: $(cat "$r/ran.log")"
else
  PASS=$((PASS+1)); echo "PASS: 4 無關檔案零執行"
fi

# 5) 不可解析的 stdin → exit 0(fail-open)
r=$WORK/r5; make_root "$r"
rc=0; printf 'not-json' | CLAUDE_PROJECT_DIR="$r" RAN_LOG="$r/ran.log" node "$HOOK" >/dev/null 2>&1 || rc=$?
check "5 壞輸入 fail-open exit 0" "$rc" '^0$'

# ---- summary ----
echo "----"
echo "validate-on-plugin-edit.test.sh: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
